import Foundation
import Combine
import Network
import Security
import OpenSSL
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class NiKHTTPSOTAServer: ObservableObject {
    static let shared = NiKHTTPSOTAServer()
    private let identityLoader: () throws -> (SecIdentity, Data)
    init(identityLoader: @escaping () throws -> (SecIdentity, Data) = { try NiKLocalTLSIdentity.loadOrCreateServer() }) {
        self.identityLoader = identityLoader
    }
    var onStop: (@MainActor () -> Void)?
    @Published private(set) var manifestRequests = 0
    @Published private(set) var ipaRequests = 0
    var manifestURL: URL? { NiKOTAURLs.manifest(port: port, token: token) }
    var landingURL: URL? {
        guard isServingIPA else { return nil }
        return URL(string: "https://127.0.0.1:\(port)/\(token)/install")
    }
    @Published private(set) var acceptedConnections = 0
    @Published private(set) var connectionError: String?
    var healthURL: URL? {
        guard isRunning else { return nil }
        return URL(string: "https://127.0.0.1:\(port)/\(token)/health")
    }
    func resetRequestCounts() {
        manifestRequests = 0; ipaRequests = 0; acceptedConnections = 0; connectionError = nil
    }

  enum OTAError: LocalizedError {
case certificateGenerationFailed
case identityImportFailed
case missingIPA

var errorDescription: String? {
switch self {
case .certificateGenerationFailed: return "Failed to generate local HTTPS certificate."
case .identityImportFailed: return "Failed to import local HTTPS identity."
case .missingIPA: return "No IPA file configured."
}
}
}

@Published private(set) var isRunning = false
@Published private(set) var port: UInt16 = 0
@Published private(set) var token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
@Published private(set) var lastError: String?

private var listener: NWListener?
private var connections: [ObjectIdentifier: NWConnection] = [:]
private var pendingHeaders = Set<ObjectIdentifier>()
#if canImport(UIKit)
private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif
private let queue = DispatchQueue(label: "com.niksign.https.ota.server", qos: .userInitiated)

private var ipaURL: URL?
private var bundleIdentifier = "com.niksign.app"
private var bundleVersion = "1.0"
private var displayTitle = "NiKSign App"

private var identity: SecIdentity?
private var certificateDER: Data?

var itmsInstallURL: URL? {
    guard isRunning, let manifestURL else { return nil }
    return NiKOTAURLs.install(manifest: manifestURL)
}
  func configure(ipaURL: URL, bundleIdentifier: String, bundleVersion: String, title: String) {
self.ipaURL = ipaURL
self.bundleIdentifier = bundleIdentifier
self.bundleVersion = bundleVersion
self.displayTitle = title
}

func start() throws { try start(requireIPA: true) }
func startTrustCheck() throws {
    ipaURL = nil // A standalone trust check must never expose a stale, unreserved IPA.
    try start(requireIPA: false)
}
var isServingIPA: Bool { isRunning && ipaURL != nil }
private func start(requireIPA: Bool) throws {
lastError = nil
if requireIPA {
    guard let ipaURL, FileManager.default.fileExists(atPath: ipaURL.path) else { throw OTAError.missingIPA }
}
stop()
resetRequestCounts()
token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
try ensureIdentity()
guard let secIdentity = identity else { throw OTAError.identityImportFailed }

let tlsOptions = NWProtocolTLS.Options()
guard let secId = sec_identity_create(secIdentity) else { throw OTAError.identityImportFailed }
sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secId)
sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
parameters.allowLocalEndpointReuse = true
parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)

let newListener = try NWListener(using: parameters)
newListener.stateUpdateHandler = { [weak self] state in
Task { @MainActor [weak self] in
guard let self, self.listener === newListener else { return }
switch state {
case .ready:
self.port = newListener.port?.rawValue ?? 0
self.isRunning = self.port > 0
self.lastError = nil
case .failed(let error):
self.lastError = error.localizedDescription
self.stop()
case .cancelled:
self.isRunning = false
default:
break
}
}
}
newListener.newConnectionHandler = { [weak self, weak newListener] connection in
    Task { @MainActor [weak self] in
        guard let self, let newListener, self.listener === newListener else {
            connection.cancel()
            return
        }
        self.handle(connection: connection)
    }
}
self.listener = newListener
#if canImport(UIKit)
backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NiKSign Local OTA") { [weak self] in
    Task { @MainActor in self?.stop() }
}
#endif
newListener.start(queue: queue)
}

func stop() {
listener?.stateUpdateHandler = nil
listener?.newConnectionHandler = nil
listener?.cancel()
listener = nil
connections.values.forEach { $0.cancel() }
connections.removeAll()
pendingHeaders.removeAll()
#if canImport(UIKit)
if backgroundTask != .invalid {
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
}
#endif
isRunning = false
port = 0
onStop?()
}

private func ensureIdentity() throws {
    if let identity {
        var certificate: SecCertificate?
        if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
           NiKTLSServerCertificate.isCurrent(SecCertificateCopyData(certificate) as Data, minimumRemaining: 3600) { return }
    }
    let generated = try identityLoader()
    identity = generated.0; certificateDER = generated.1
}
func exportMobileConfig() throws -> Data {
    let oldRoot = certificateDER
    try ensureIdentity()
    if let oldRoot, oldRoot != certificateDER, isRunning { stop() }
    guard let certificateDER else { throw OTAError.certificateGenerationFailed }
    return try NiKOTAProfile.encode(certificateDER: certificateDER)
}
func waitUntilReady() async throws {
    for _ in 0..<200 {
        if isRunning { return }
        if lastError != nil || listener == nil { throw OTAError.identityImportFailed }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    stop()
    throw OTAError.identityImportFailed
}

func openInstallURL() async -> Bool {
    #if canImport(UIKit)
    guard let url = itmsInstallURL else { lastError = "Máy chủ cài đặt chưa sẵn sàng."; return false }
    return await withCheckedContinuation { continuation in
        UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
    }
    #else
    return false
    #endif
}

private func handle(connection: NWConnection) {
    guard connections.count < 8 else { connection.cancel(); return }
    let id = ObjectIdentifier(connection)
    acceptedConnections += 1
    connections[id] = connection
    pendingHeaders.insert(id)
    connection.stateUpdateHandler = { [weak self, weak connection] state in
        if case .cancelled = state {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connections[id] === connection else { return }
                self.connections.removeValue(forKey: id); self.pendingHeaders.remove(id)
            }
        }
        if case .failed(let error) = state {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connections[id] === connection else { return }
                self.connectionError = error.localizedDescription
                connection.cancel()
            }
        }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
        Task { @MainActor in
            guard let self, self.pendingHeaders.contains(id) else { return }
            connection?.cancel()
        }
    }
    receiveRequest(connection: connection, buffer: Data())
}

private func receiveRequest(connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384 - buffer.count) { [weak self] data, _, complete, error in
        Task { @MainActor [weak self] in
            guard let self, self.listener != nil,
                  self.connections[ObjectIdentifier(connection)] === connection,
                  error == nil, let data, !data.isEmpty else { connection.cancel(); return }
            var request = buffer
            request.append(data)
            guard let end = request.range(of: Data("\r\n\r\n".utf8)) else {
                guard !complete, request.count < 16_384 else { connection.cancel(); return }
                self.receiveRequest(connection: connection, buffer: request)
                return
            }
            self.pendingHeaders.remove(ObjectIdentifier(connection))
            guard let header = String(data: request[..<end.lowerBound], encoding: .utf8),
                  let parsed = try? NiKOTAHTTP.Request(header) else {
                self.sendResponse(on: connection, status: "400 Bad Request", contentType: "text/plain", body: Data())
                return
            }
            guard ["GET", "HEAD"].contains(parsed.method) else {
                self.sendResponse(on: connection, status: "405 Method Not Allowed", contentType: "text/plain", body: Data(), extraHeaders: "Allow: GET, HEAD\r\n")
                return
            }
            let path = parsed.path, head = parsed.method == "HEAD"
            if path == "/\(self.token)/health" {
                self.sendResponse(on: connection, status: "200 OK", contentType: "text/plain", body: Data("NiKSign Local HTTPS".utf8), head: head)
            } else if path == "/\(self.token)/install", self.ipaURL != nil, let link = self.itmsInstallURL {
                let html = NiKOTALandingPage.html(title: self.displayTitle, bundleID: self.bundleIdentifier, installURL: link)
                self.sendResponse(on: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8), head: head)
            } else if path == "/\(self.token)/manifest.plist", self.ipaURL != nil {
                self.manifestRequests += 1
                do {
                    let plist = try self.manifestPlistData()
                    self.sendResponse(on: connection, status: "200 OK", contentType: "application/xml", body: plist, head: head)
                } catch { connection.cancel() }
            } else if path == "/\(self.token)/app.ipa", let url = self.ipaURL {
                self.ipaRequests += 1
                self.sendFile(on: connection, url: url, head: head, range: parsed.headers["if-range"] == nil && !head ? parsed.headers["range"] : nil)
            } else {
                self.sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data())
            }
        }
    }
}

private func manifestPlistData() throws -> Data {
    guard let url = URL(string: "https://127.0.0.1:\(port)/\(token)/app.ipa") else { throw OTAError.missingIPA }
    return try NiKOTAHTTP.manifest(ipaURL: url, bundleID: bundleIdentifier, buildVersion: bundleVersion, title: displayTitle)
}

private func sendFile(on connection: NWConnection, url: URL, head: Bool, range: String?) {
    do {
        let handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        let response = NiKOTAHTTP.FileResponse.make(size: size, range: range)
        try handle.seek(toOffset: response.offset)
        let rangeHeader = response.contentRange.map { "Content-Range: \($0)\r\n" } ?? ""
        let header = "HTTP/1.1 \(response.status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(response.length)\r\nAccept-Ranges: bytes\r\n\(rangeHeader)Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            guard !head, response.length > 0 else { try? handle.close(); Self.finish(connection); return }
            Self.sendNextChunk(on: connection, handle: handle, remaining: response.length)
        })
    } catch {
        sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data("IPA unavailable".utf8))
    }
}

nonisolated private static func sendNextChunk(on connection: NWConnection, handle: FileHandle, remaining: UInt64) {
    guard remaining > 0 else { try? handle.close(); finish(connection); return }
    do {
        guard let data = try handle.read(upToCount: Int(min(remaining, 65536))), !data.isEmpty else {
            try? handle.close(); connection.cancel(); return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            sendNextChunk(on: connection, handle: handle, remaining: remaining - UInt64(data.count))
        })
    } catch { try? handle.close(); connection.cancel() }
}

private func sendResponse(on connection: NWConnection, status: String, contentType: String, body: Data, head: Bool = false, extraHeaders: String = "") {
let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n\(extraHeaders)Connection: close\r\n\r\n"
var payload = Data(header.utf8)
if !head { payload.append(body) }
connection.send(content: payload, completion: .contentProcessed { error in
    if error != nil { connection.cancel() } else { Self.finish(connection) }
})
}

// Half-close only after all bytes have been enqueued; drain the peer's EOF.
// Immediate cancel can abort a queued response, particularly the last IPA chunk.
nonisolated private static func finish(_ connection: NWConnection) {
    connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
        guard error == nil else { connection.cancel(); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
    })
    DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak connection] in connection?.cancel() }
}

}
