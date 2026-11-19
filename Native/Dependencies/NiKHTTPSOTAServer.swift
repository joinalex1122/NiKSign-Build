import Foundation
import Combine
import Network
import Security
import OpenSSL
import UIKit

@MainActor
final class NiKHTTPSOTAServer: ObservableObject {
    static let shared = NiKHTTPSOTAServer()
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
private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
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
if identity == nil || certificateDER == nil {
    let generated = try NiKLocalTLSIdentity.loadOrCreateServer()
    identity = generated.0
    certificateDER = generated.1
}
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
backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NiKSign Local OTA") { [weak self] in
    Task { @MainActor in self?.stop() }
}
newListener.start(queue: queue)
}

func stop() {
listener?.stateUpdateHandler = nil
listener?.newConnectionHandler = nil
listener?.cancel()
listener = nil
connections.values.forEach { $0.cancel() }
connections.removeAll()
if backgroundTask != .invalid {
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
}
isRunning = false
port = 0
onStop?()
}

func exportMobileConfig() throws -> Data {
let certData: Data
if let existing = certificateDER {
certData = existing
} else {
let (secIdentity, der) = try NiKLocalTLSIdentity.loadOrCreateServer()
self.identity = secIdentity
self.certificateDER = der
certData = der
}
return try NiKOTAProfile.encode(certificateDER: certData)
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
    guard let url = itmsInstallURL else { lastError = "Máy chủ cài đặt chưa sẵn sàng."; return false }
    return await withCheckedContinuation { continuation in
        UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
    }
}

private func handle(connection: NWConnection) {
    guard connections.count < 8 else { connection.cancel(); return }
    let id = ObjectIdentifier(connection)
    acceptedConnections += 1
    connections[id] = connection
    connection.stateUpdateHandler = { [weak self, weak connection] state in
        if case .cancelled = state { Task { @MainActor in self?.connections.removeValue(forKey: id) } }
        if case .failed(let error) = state {
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.connections[id] === connection else { return }
                self.connectionError = error.localizedDescription
                connection.cancel()
            }
        }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 120) { [weak connection] in connection?.cancel() }
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
            guard let header = String(data: request[..<end.lowerBound], encoding: .utf8),
                  let line = header.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count == 3, ["GET", "HEAD"].contains(parts[0]), parts[2].hasPrefix("HTTP/1.") else {
                self.sendResponse(on: connection, status: "405 Method Not Allowed", contentType: "text/plain", body: Data())
                return
            }
            let path = String(parts[1]), head = parts[0] == "HEAD"
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
                self.sendFile(on: connection, url: url, head: head)
            } else {
                self.sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data())
            }
        }
    }
}

private func manifestPlistData() throws -> Data {
let ipaAddress = "https://127.0.0.1:\(port)/\(token)/app.ipa"
let manifest: [String: Any] = [
"items": [[
"assets": [[
"kind": "software-package",
"url": ipaAddress
]],
"metadata": [
"bundle-identifier": bundleIdentifier,
"bundle-version": bundleVersion,
"kind": "software",
"title": displayTitle
]
]]
]
return try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
}

private func sendFile(on connection: NWConnection, url: URL, head: Bool) {
    do {
        let handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            guard error == nil, !head else { try? handle.close(); connection.cancel(); return }
            Self.sendNextChunk(on: connection, handle: handle, remaining: size)
        })
    } catch {
        sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data("IPA unavailable".utf8))
    }
}

nonisolated private static func sendNextChunk(on connection: NWConnection, handle: FileHandle, remaining: UInt64) {
    guard remaining > 0 else { try? handle.close(); connection.cancel(); return }
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

private func sendResponse(on connection: NWConnection, status: String, contentType: String, body: Data, head: Bool = false) {
let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
var payload = Data(header.utf8)
if !head { payload.append(body) }
connection.send(content: payload, completion: .contentProcessed { _ in
connection.cancel()
})
}

}
