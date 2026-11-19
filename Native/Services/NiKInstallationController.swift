import Foundation
import Combine
import UIKit

@MainActor final class NiKInstallationController: ObservableObject {
    static let shared = NiKInstallationController()
    enum Phase { case idle, preparing, trustRequired, ready, requestSent, failed }
    var isInstallerRunning: Bool { server.isServingIPA }
    enum TrustState { case unknown, checking, trusted, required, unavailable }
    @Published private(set) var trustState: TrustState = .unknown
    @Published private(set) var trustError: String?
    @Published private(set) var deliveryNotice: String?
    private var deliveryTask: Task<Void, Never>?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var metadata: NiKInstallMetadata?
    @Published private(set) var fileURL: URL?
    let server = NiKHTTPSOTAServer.shared
    private let profileServer = NiKLoopbackServer()
    private var payload: NiKInstallationPayload?
    private var lease: NiKFileMutationReservations.Lease?

    private init() {
        NiKInstallationPayload.recoverAbandoned()
        server.onStop = { [weak self] in
            guard let self else { return }
            self.releaseLease(); self.payload?.discard(); self.payload = nil
        }

    }
    private func releaseLease() {
        if let lease { NiKFileMutationReservations.shared.release(lease); self.lease = nil }
    }
    func stop() {
        deliveryTask?.cancel(); deliveryTask = nil; deliveryNotice = nil
        profileServer.stop(); server.stop(); releaseLease()
        payload?.discard(); payload = nil
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
            let worker = Task.detached { try NiKInstallationPayload.prepare(local) }
            let snapshot = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            var adopted = false
            defer { if !adopted { snapshot.discard() } }
            try Task.checkCancellation()
            let info = snapshot.metadata
            metadata = info
            server.configure(ipaURL: snapshot.url, bundleIdentifier: info.bundleID, bundleVersion: info.version, title: info.title)
            try server.start()
            payload = snapshot; adopted = true
            lease = held; transferred = true
            try await server.waitUntilReady()
            try Task.checkCancellation()
            await probeHTTPS()
        } catch is CancellationError { stop() }
        catch { stop(); phase = .failed; self.error = error.localizedDescription }
    }
    func checkConnection() async {
        guard !busy, let fileURL else { return }
        if !isInstallerRunning { await prepare(fileURL); return }
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
            trustState = .trusted
            phase = .ready
        } catch {
            if Task.isCancelled { stop(); return }
            if Self.requiresTrust(error) {
                phase = .trustRequired; trustState = .required
            } else { phase = .failed }
            trustError = error.localizedDescription
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
        let accepted = await server.openInstallURL()
        if accepted { phase = .requestSent; observeDelivery() }
        else { phase = .failed; error = "iOS không nhận liên kết itms-services. Hãy kiểm tra giới hạn cài đặt/MDM trên thiết bị." }
    }
    func checkTrust() async {
        guard !busy else { return }
        busy = true; trustState = .checking; trustError = nil
        defer { busy = false }
        do {
            if !server.isRunning {
                try server.startTrustCheck()
                try await server.waitUntilReady()
            }
            guard let url = server.healthURL else { throw NiKError("Máy chủ HTTPS chưa sẵn sàng.") }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data == Data("NiKSign Local HTTPS".utf8) else { throw NiKError("Phản hồi kiểm tra HTTPS không hợp lệ.") }
            trustState = .trusted
        } catch {
            trustState = Self.requiresTrust(error) ? .required : .unavailable
            trustError = error.localizedDescription
        }
    }
    private static func requiresTrust(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSURLErrorDomain && [NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed].contains(value.code)
    }
    private func observeDelivery() {
        deliveryTask?.cancel(); deliveryNotice = nil
        deliveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.phase == .requestSent else { return }
            if !self.server.isRunning {
                self.deliveryNotice = "Máy chủ đã dừng trước khi hoàn tất tải. Quay lại NiKSign, chuẩn bị lại rồi cài."
            } else if self.server.manifestRequests == 0 {
                self.deliveryNotice = self.server.acceptedConnections == 0
                    ? "iOS chưa kết nối tới máy chủ cài đặt. Giữ NiKSign mở và thử lại; mở liên kết chưa có nghĩa là cài thành công."
                    : "Có kết nối nhưng chưa đọc được manifest. Kiểm tra tin cậy HTTPS trong Cài đặt và thử lại."
            } else if self.server.ipaRequests == 0 {
                self.deliveryNotice = "Đã có yêu cầu manifest nhưng chưa có yêu cầu tải IPA. iOS có thể đã từ chối yêu cầu cài; kiểm tra hồ sơ tin cậy và chứng chỉ ký."
            }
        }
    }
    func downloadTrustProfile() async {
        guard !busy else { return }
        busy = true; trustError = nil; defer { busy = false }
        do {
            let data = try server.exportMobileConfig()
            guard let url = profileServer.startTrustProfile(data: data) else { throw NiKError("Không mở được máy chủ tải hồ sơ HTTPS.") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 10
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (received, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, received == data else {
                throw NiKError("Máy chủ tải hồ sơ chưa phản hồi đúng. Quay lại NiKSign và thử tải lại.")
            }
            let accepted = await UIApplication.shared.open(url, options: [:])
            if !accepted { throw NiKError("Không mở được Safari để tải hồ sơ.") }
        } catch { self.error = error.localizedDescription; trustError = error.localizedDescription }
    }
}
