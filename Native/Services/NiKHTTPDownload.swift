import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral, bounded HTTP(S) transfer into an owned staging directory.
final class NiKHTTPDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Progress: Sendable { let bytes: Int64; let expectedBytes: Int64? }
    struct Receipt: Sendable {
        let url: URL
        let directory: URL
        let bytes: Int64
        func discard() throws { try FileManager.default.removeItem(at: directory) }
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private let limit: Int64
    private let timeout: TimeInterval
    private let progress: @Sendable (Progress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Receipt, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var directory: URL?
    private var output: URL?
    private var file: FileHandle?
    private var bytes: Int64 = 0
    private var expectedBytes: Int64?
    private var failure: Error?
    private var cancelled = false
    private var finished = false
    private var accepted = false
    private var redirects = 0
    private var lastProgressTime: TimeInterval = 0

    private init(limit: Int64, timeout: TimeInterval, progress: @escaping @Sendable (Progress) -> Void) {
        self.limit = limit; self.timeout = timeout; self.progress = progress
    }
    static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw Failure(message: "URL phải là HTTP/HTTPS và không chứa tài khoản/mật khẩu.")
        }
    }
    static func download(_ url: URL, limit: Int64, timeout: TimeInterval = 60,
                         progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Receipt {
        try validate(url)
        guard limit > 0, limit <= 1_073_741_824, timeout.isFinite, timeout > 0 else {
            throw Failure(message: "Giới hạn tải không hợp lệ.")
        }
        let transfer = NiKHTTPDownload(limit: limit, timeout: timeout, progress: progress)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { transfer.start(url, continuation: $0) }
        }, onCancel: { transfer.cancel() })
    }
    private func start(_ url: URL, continuation: CheckedContinuation<Receipt, Error>) {
        lock.lock()
        self.continuation = continuation
        if cancelled {
            lock.unlock(); finish(CancellationError()); return
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NiKSign-Network-" + UUID().uuidString, isDirectory: true)
            self.directory = directory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let output = directory.appendingPathComponent("payload.download")
            self.output = output
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw Failure(message: "Không tạo được tệp tải tạm.")
            }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
            #endif
            file = try FileHandle(forWritingTo: output)
            let config = URLSessionConfiguration.ephemeral
            config.urlCredentialStorage = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = min(timeout, 60)
            config.timeoutIntervalForResource = timeout
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            self.session = session
            task = session.dataTask(with: url)
            let task = self.task
            lock.unlock()
            task?.resume()
        } catch { lock.unlock(); finish(error) }
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           response.expectedContentLength <= limit, !cancelled, !finished {
            accepted = true
            expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            lock.unlock(); completionHandler(.allow)
        } else {
            if cancelled { failure = CancellationError() }
            else if response.expectedContentLength > limit { failure = Failure(message: "Máy chủ trả về tệp vượt giới hạn tải.") }
            else { failure = Failure(message: "Tải thất bại: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).") }
            lock.unlock(); completionHandler(.cancel)
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished, !cancelled, failure == nil, accepted else { lock.unlock(); dataTask.cancel(); return }
        do {
            guard Int64(data.count) <= limit - bytes else { throw Failure(message: "Nội dung tải vượt giới hạn.") }
            guard let file else { throw Failure(message: "Tệp tải tạm chưa sẵn sàng.") }
            try file.write(contentsOf: data)
            bytes += Int64(data.count)
            let update = Progress(bytes: bytes, expectedBytes: expectedBytes)
            let now = ProcessInfo.processInfo.systemUptime
            let shouldReport = lastProgressTime == 0 || now - lastProgressTime >= 0.1
            if shouldReport { lastProgressTime = now }
            lock.unlock()
            if shouldReport { progress(update) }
        } catch { failure = error; lock.unlock(); dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        do {
            redirects += 1
            guard redirects <= 5, let destination = request.url else { throw Failure(message: "Nguồn chuyển hướng quá 5 lần.") }
            try Self.validate(destination)
            guard !(response.url?.scheme?.lowercased() == "https" && destination.scheme?.lowercased() != "https") else {
                throw Failure(message: "Từ chối chuyển từ HTTPS xuống HTTP.")
            }
            guard !cancelled, !finished else { throw CancellationError() }
            lock.unlock(); completionHandler(request)
        } catch { failure = error; lock.unlock(); completionHandler(nil); task.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }
    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        var finalError = failure ?? (cancelled ? CancellationError() : error)
        do { try file?.close() } catch { if finalError == nil { finalError = error } }
        file = nil
        if finalError == nil && (!accepted || bytes == 0) { finalError = Failure(message: "Tệp tải rỗng hoặc phản hồi không hợp lệ.") }
        let receipt: Receipt? = output.flatMap { output in directory.map { Receipt(url: output, directory: $0, bytes: bytes) } }
        let stagingDirectory = directory, pendingContinuation = continuation, activeSession = session
        let finalProgress = Progress(bytes: bytes, expectedBytes: expectedBytes)
        self.continuation = nil; self.session = nil; self.task = nil
        lock.unlock()
        activeSession?.invalidateAndCancel()
        if let finalError {
            if let stagingDirectory { try? FileManager.default.removeItem(at: stagingDirectory) }
            pendingContinuation?.resume(throwing: finalError)
        } else if let receipt { progress(finalProgress); pendingContinuation?.resume(returning: receipt) }
        else { pendingContinuation?.resume(throwing: Failure(message: "Không có kết quả tải.")) }
    }
}
