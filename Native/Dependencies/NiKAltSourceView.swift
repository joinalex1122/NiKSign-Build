import Foundation
import SwiftUI

struct NiKAltSourceApp: Identifiable, Hashable {
    var id: String { "\(sourceURL.absoluteString)#\(bundleIdentifier)#\(version)" }
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let version: String
    let versionDate: String?
    let sizeBytes: Int64?
    let downloadURL: URL
    let iconURL: URL?
    let localizedDescription: String
    let sourceName: String
    let sourceURL: URL
}

struct NiKAltSourceFeed: Codable {
    struct AppEntry: Codable {
        struct VersionEntry: Codable {
            let version: String?
            let date: String?
            let size: Int64?
            let downloadURL: URL?
            let localizedDescription: String?
        }
        let name: String?
        let bundleIdentifier: String?
        let developerName: String?
        let version: String?
        let versionDate: String?
        let size: Int64?
        let downloadURL: URL?
        let iconURL: URL?
        let localizedDescription: String?
        let subtitle: String?
        let versions: [VersionEntry]?
    }
    let name: String?
    let subtitle: String?
    let description: String?
    let apps: [AppEntry]?
}

@MainActor
final class NiKAltSourceStore: ObservableObject {
    @Published private(set) var sourceURLs: [URL] = []
    @Published private(set) var apps: [NiKAltSourceApp] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let storageKey = "niksign.altsource.urls"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            sourceURLs = saved.compactMap(URL.init(string:))
        }
    }

    func addSource(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            errorMessage = "URL nguồn AltSource không hợp lệ (cần http/https)."
            return
        }
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
        guard !sourceURLs.isEmpty else {
            apps = []
            return
        }
        isLoading = true
        errorMessage = nil
        var collected: [NiKAltSourceApp] = []
        for url in sourceURLs {
            do {
                let parsed = try await Self.fetchSource(from: url)
                collected.append(contentsOf: parsed)
            } catch {
                errorMessage = "Lỗi tải \(url.host ?? url.absoluteString): \(error.localizedDescription)"
            }
        }
        apps = collected
        isLoading = false
    }

    private func persistURLs() {
        UserDefaults.standard.set(sourceURLs.map(\.absoluteString), forKey: storageKey)
    }

    nonisolated static func parseFeed(data: Data, sourceURL: URL) throws -> [NiKAltSourceApp] {
        let feed = try JSONDecoder().decode(NiKAltSourceFeed.self, from: data)
        let sourceTitle = feed.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? feed.name!
            : (sourceURL.host ?? "AltSource")
        var result: [NiKAltSourceApp] = []
        for entry in feed.apps ?? [] {
            guard let appName = entry.name, !appName.isEmpty,
                  let bundleID = entry.bundleIdentifier, !bundleID.isEmpty else {
                continue
            }
            let latestVersion = entry.versions?.first
            guard let downloadURL = latestVersion?.downloadURL ?? entry.downloadURL else {
                continue
            }
            let version = latestVersion?.version ?? entry.version ?? "1.0"
            let date = latestVersion?.date ?? entry.versionDate
            let size = latestVersion?.size ?? entry.size
            let desc = latestVersion?.localizedDescription ?? entry.localizedDescription ?? entry.subtitle ?? ""
            result.append(
                NiKAltSourceApp(
                    name: appName,
                    bundleIdentifier: bundleID,
                    developerName: entry.developerName ?? sourceTitle,
                    version: version,
                    versionDate: date,
                    sizeBytes: size,
                    downloadURL: downloadURL,
                    iconURL: entry.iconURL,
                    localizedDescription: desc,
                    sourceName: sourceTitle,
                    sourceURL: sourceURL
                )
            )
        }
        return result
    }

    nonisolated static func fetchSource(from url: URL) async throws -> [NiKAltSourceApp] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NiKError("Máy chủ trả về mã HTTP \(http.statusCode).")
        }
        guard data.count <= 16_777_216 else {
            throw NiKError("JSON nguồn vượt giới hạn 16 MB.")
        }
        return try parseFeed(data: data, sourceURL: url)
    }

    nonisolated static func downloadIPA(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NiKError("Tải IPA thất bại (HTTP \(http.statusCode)).")
        }
        let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 1_073_741_824 else {
            throw NiKError("IPA tải về rỗng hoặc vượt giới hạn 1 GB.")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("AltSource-\(UUID().uuidString).ipa")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        return destination
    }
}

struct NiKAltSourceView: View {
    @ObservedObject var store: NiKAltSourceStore
    var onSelectDownloadedIPA: (URL, NiKAltSourceApp) -> Void

    @State private var newSourceURL = ""
    @State private var searchText = ""
    @State private var downloadingAppID: String?
    @State private var statusMessage = ""

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
            Section("Thêm nguồn AltSource / Feather JSON") {
                HStack {
                    TextField("https://.../apps.json", text: $newSourceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Thêm") {
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

            if !store.sourceURLs.isEmpty {
                Section("Nguồn đang theo dõi (\(store.sourceURLs.count))") {
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

            Section("Ứng dụng IPA (\(filteredApps.count))") {
                if store.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang đồng bộ danh mục AltSource…").font(.caption)
                    }
                } else if filteredApps.isEmpty {
                    Text("Chưa có ứng dụng nào. Hãy thêm URL nguồn JSON theo chuẩn AltStore/Feather để duyệt và đưa thẳng vào trình ký.")
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
                                        Label("Tải & Ký", systemImage: "arrow.down.circle.fill")
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
        .searchable(text: $searchText, prompt: "Tìm tên app, Bundle ID, tác giả…")
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
        downloadingAppID = app.id
        statusMessage = "Đang tải \(app.name) (v\(app.version))…"
        Task {
            defer { downloadingAppID = nil }
            do {
                let fileURL = try await NiKAltSourceStore.downloadIPA(from: app.downloadURL)
                statusMessage = "Đã tải xong \(app.name). Đã chuyển sang tab Ký IPA."
                onSelectDownloadedIPA(fileURL, app)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
