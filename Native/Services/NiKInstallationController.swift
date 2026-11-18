import Foundation
import Combine
import UIKit

@MainActor final class NiKInstallationController: ObservableObject {
    static let shared = NiKInstallationController()
    enum Phase { case idle, preparing, trustRequired, ready, requestSent, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var metadata: NiKInstallMetadata?
    @Published private(set) var fileURL: URL?
    let server = NiKHTTPSOTAServer.shared
    private let profileServer = NiKLoopbackServer()
    private var lease: NiKFileMutationReservations.Lease?

    init() { server.onStop = { [weak self] in self?.releaseLease() } }
    private func releaseLease() {
        if let lease { NiKFileMutationReservations.shared.release(lease); self.lease = nil }
    }
    func stop() {
        profileServer.stop(); server.stop(); releaseLease()
        phase = .idle
    }
    func prepare(_ url: URL) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        stop(); fileURL = url; metadata = nil; error = nil; phase = .preparing
        do {
            guard let local = NiKSignedFileAccess.available(url.path) else { throw NiKError("Không tìm thấy IPA trong Signed. Khôi phục tệp hoặc ký lại.") }
            let held = try NiKFileMutationReservations.shared.reserve([local])
            var transferred = false
            defer { if !transferred { NiKFileMutationReservations.shared.release(held) } }
            let worker = Task.detached { try NiKInstallMetadata.read(local) }
            let info = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            metadata = info
            server.configure(ipaURL: local, bundleIdentifier: info.bundleID, bundleVersion: info.version, title: info.title)
            try server.start()
            lease = held; transferred = true
            try await server.waitUntilReady()
            try Task.checkCancellation()
            await probeHTTPS()
        } catch is CancellationError { stop() }
        catch { stop(); phase = .failed; self.error = error.localizedDescription }
    }
    func checkConnection() async {
        guard !busy, let fileURL else { return }
        if !server.isRunning { await prepare(fileURL); return }
        busy = true; defer { busy = false }
        await probeHTTPS()
    }
    private func probeHTTPS() async {
        error = nil
        do {
            guard let url = server.manifestURL, server.isRunning else { throw NiKError("Máy chủ HTTPS chưa sẵn sàng. Hãy chuẩn bị lại.") }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            // Default system TLS validation. Never accept self-signed certificates in a delegate.
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 65536,
                  let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let items = plist["items"] as? [[String: Any]], items.count == 1,
                  let info = items[0]["metadata"] as? [String: Any],
                  info["bundle-identifier"] as? String == metadata?.bundleID else { throw NiKError("Không đọc được manifest cài đặt đúng ứng dụng.") }
            phase = .ready
        } catch {
            if Task.isCancelled { stop(); return }
            let code = (error as NSError).code
            if (error as NSError).domain == NSURLErrorDomain,
               [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid].contains(code) {
                phase = .trustRequired
            } else { phase = .failed }
            self.error = error.localizedDescription
        }
    }
    func install() async {
        guard !busy else { return }
        await checkConnection()
        guard phase == .ready, !busy else { return }
        guard UIApplication.shared.applicationState == .active else {
            phase = .failed; error = "Quay lại NiKSign rồi bấm Cài đặt khi ứng dụng đang mở."; return
        }
        busy = true; defer { busy = false }
        server.resetRequestCounts()
        if await server.openInstallURL() { phase = .requestSent }
        else { phase = .failed; error = "iOS không nhận liên kết itms-services. Hãy kiểm tra giới hạn cài đặt/MDM trên thiết bị." }
    }
    func downloadTrustProfile() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let data = try server.exportMobileConfig()
            guard let url = profileServer.startTrustProfile(data: data) else { throw NiKError("Không mở được máy chủ tải hồ sơ HTTPS.") }
            let accepted = await UIApplication.shared.open(url, options: [:])
            if !accepted { throw NiKError("Không mở được Safari để tải hồ sơ.") }
        } catch { self.error = error.localizedDescription }
    }
}
