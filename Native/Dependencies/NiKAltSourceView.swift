import Foundation
import SwiftUI

@MainActor
final class NiKAltSourceStore: ObservableObject {
    @Published private(set) var sourceURLs: [URL] = []
    @Published private(set) var apps: [NiKAltSourceApp] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let storageKey = "niksign.altsource.urls"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            var unique = Set<URL>()
            sourceURLs = saved.prefix(40).compactMap { raw in
                guard let url = URL(string: raw), (try? NiKHTTPDownload.validate(url)) != nil,
                      unique.insert(url).inserted else { return nil }
                return url
            }
        }
    }

    func addSource(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), (try? NiKHTTPDownload.validate(url)) != nil else {
            errorMessage = "URL cần HTTP/HTTPS và không chứa tài khoản/mật khẩu."
            return
        }
        guard sourceURLs.contains(url) || sourceURLs.count < 40 else { errorMessage = "Tối đa 40 nguồn."; return }
        if !sourceURLs.contains(url) {
            sourceURLs.append(url)
            persistURLs()
        }
        await refreshAll()
    }

    func removeSource(_ url: URL) {
        sourceURLs.removeAll { $0 == url }
        apps.removeAll { $0.sourceURL == url }
        persistURLs()
    }

    func refreshAll() async {
        guard !isLoading else { return }
        guard !sourceURLs.isEmpty else { apps = []; return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let previous = apps, requested = sourceURLs
        var collected: [NiKAltSourceApp] = []
        var errors: [String] = []
        for url in requested {
            do {
                try Task.checkCancellation()
                collected.append(contentsOf: try await Self.fetchSource(from: url))
            } catch is CancellationError { return }
            catch {
                errors.append("Lỗi tải \(url.host ?? "nguồn"): \(error.localizedDescription)")
                collected.append(contentsOf: previous.filter { $0.sourceURL == url })
            }
        }
        apps = collected.filter { sourceURLs.contains($0.sourceURL) }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func persistURLs() {
        UserDefaults.standard.set(sourceURLs.map(\.absoluteString), forKey: storageKey)
    }

    nonisolated static func parseFeed(data: Data, sourceURL: URL) throws -> [NiKAltSourceApp] {
        try NiKSourceDownloadService.parseFeed(data: data, sourceURL: sourceURL)
    }
    nonisolated static func fetchSource(from url: URL) async throws -> [NiKAltSourceApp] {
        try await NiKSourceDownloadService.fetchFeed(url)
    }

}

struct NiKAltSourceView: View {
    @ObservedObject var store: NiKAltSourceStore
    var onSelectDownloadedIPA: (URL, NiKAltSourceApp) async throws -> Void

    @AppStorage("nik.language") private var language = "vi"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    @State private var newSourceURL = ""
    @State private var searchText = ""
    @State private var downloadingAppID: String?
    @State private var statusMessage = ""
    @State private var downloadTask: Task<Void, Never>?
    @State private var receivedBytes: Int64 = 0
    @State private var expectedBytes: Int64?


    private var filteredApps: [NiKAltSourceApp] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.apps }
        return store.apps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
                || $0.developerName.localizedCaseInsensitiveContains(q)
                || $0.sourceName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            Section(t("Thêm nguồn AltSource / Feather JSON", "Add AltSource / Feather JSON Source")) {
                HStack {
                    TextField("https://.../apps.json", text: $newSourceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(t("Thêm", "Add")) {
                        let urlToLoad = newSourceURL
                        newSourceURL = ""
                        Task { await store.addSource(urlString: urlToLoad) }
                    }
                    .disabled(newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLoading)
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            if downloadingAppID != nil {
                Section(t("Đang tải", "Downloading")) {
                    if let expectedBytes { ProgressView(value: Double(receivedBytes), total: Double(max(1, expectedBytes))) }
                    else { ProgressView() }
                    Text(ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)).font(.caption)
                    Button(t("Hủy tải", "Cancel Download"), role: .destructive) { downloadTask?.cancel() }
                }
            }
            if !store.sourceURLs.isEmpty {
                Section(t("Nguồn đang theo dõi", "Subscribed Sources") + " (\(store.sourceURLs.count))") {
                    ForEach(store.sourceURLs, id: \.self) { url in
                        HStack {
                            Text(url.absoluteString)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                store.removeSource(url)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section(t("Ứng dụng IPA", "IPA Apps") + " (\(filteredApps.count))") {
                if store.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(t("Đang đồng bộ danh mục AltSource…", "Refreshing source catalog…")).font(.caption)
                    }
                } else if filteredApps.isEmpty {
                    Text(t("Chưa có ứng dụng. Thêm nguồn AltStore/Feather JSON để tải vào thư viện. Không tự ký hoặc cài đặt.", "No apps yet. Add an AltStore/Feather JSON source to download into the library. Signing and installation require separate actions."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredApps) { app in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.headline)
                                    Text("\(app.developerName) · v\(app.version) · \(app.sourceName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let size = app.sizeBytes {
                                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if app.downloadURL.scheme?.lowercased() == "http" {
                                        Text(t("Liên kết tải HTTP chưa mã hóa", "Download uses unencrypted HTTP")).font(.caption2).foregroundStyle(.orange)
                                    }
                                    Text(app.sha256 == nil ? t("Nguồn không cung cấp SHA-256", "No SHA-256 provided by source") : t("Có SHA-256 từ nguồn", "Source provides SHA-256")).font(.caption2).foregroundStyle(.secondary)
                                    Text(app.bundleIdentifier)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    downloadAndQueue(app)
                                } label: {
                                    if downloadingAppID == app.id {
                                        ProgressView()
                                    } else {
                                        Label(t("Tải vào thư viện", "Download to Library"), systemImage: "arrow.down.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(downloadingAppID != nil)
                            }
                            if !app.localizedDescription.isEmpty {
                                Text(app.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: t("Tìm tên app, Bundle ID, tác giả…", "Search app, bundle ID, developer…"))
        .onDisappear { downloadTask?.cancel() }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .refreshable {
            await store.refreshAll()
        }
        .task {
            if store.apps.isEmpty && !store.sourceURLs.isEmpty {
                await store.refreshAll()
            }
        }
    }

    private func downloadAndQueue(_ app: NiKAltSourceApp) {
        guard downloadingAppID == nil else { return }
        downloadingAppID = app.id; receivedBytes = 0; expectedBytes = nil
        statusMessage = t("Đang tải", "Downloading") + " \(app.name) (v\(app.version))…"
        downloadTask = Task {
            defer { downloadingAppID = nil; downloadTask = nil }
            do {
                let downloaded = try await NiKSourceDownloadService.downloadIPA(app.downloadURL, expectedSHA256: app.sha256) { update in
                    Task { @MainActor in
                        guard downloadingAppID == app.id else { return }
                        receivedBytes = update.bytes; expectedBytes = update.expectedBytes
                    }
                }
                defer { try? downloaded.discard() }
                try Task.checkCancellation()
                statusMessage = t("Đang kiểm tra và nhập IPA…", "Validating and importing IPA…")
                try await onSelectDownloadedIPA(downloaded.url, app)
                statusMessage = t("Đã nhập", "Imported") + " \(app.name). SHA-256: \(downloaded.sha256)"
            } catch is CancellationError { statusMessage = t("Đã hủy tải.", "Download cancelled.") }
            catch { statusMessage = error.localizedDescription }
        }
    }
}

struct NiKSourceLibraryView: View {
    @ObservedObject var library: NiKLibrary
    @StateObject private var sources = NiKAltSourceStore()
    @AppStorage("nik.language") private var language = "vi"
    var body: some View {
        NiKAltSourceView(store: sources) { url, app in
            guard await library.receive(url, expectedBundleID: app.bundleIdentifier) else {
                try Task.checkCancellation()
                throw NiKError(library.error.isEmpty ? "Không nhập được IPA." : library.error)
            }
        }.navigationTitle(language == "en" ? "IPA Sources" : "Nguồn IPA")
    }
}
