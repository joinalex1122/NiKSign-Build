import SwiftUI
import UIKit

struct NiKHubPreview: View {
    @AppStorage("nik.language") private var language = "vi"
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @State private var section = 0
    @State private var show3105Settings = false
    @State private var show3105Logs = false

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    var body: some View {
        
            VStack(spacing: 0) {
                Picker(t("Nhóm", "Group"), selection: $section) {
                    Text(t("Kho 3105", "Store")).tag(0)
                    Text(t("Nguồn", "Sources")).tag(1)
                    Text(t("Dự án", "Projects")).tag(2)
                    Text(t("Công cụ", "Tools")).tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground))

                Group {
                    switch section {
                    case 0:
                        RepositoryHomeView(
                            onOpenSettings: { show3105Settings = true },
                            onOpenLogs: { show3105Logs = true }
                        )
                    case 1:
                        RepositorySourcesView(
                            onOpenSettings: { show3105Settings = true },
                            onOpenLogs: { show3105Logs = true }
                        )
                    case 2:
                        PatchProjectsView()
                    default:
                        NavigationStack {
                                         NiK3105ToolsDashboardView()
                        .navigationTitle("3105")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
            }
            
            
            .sheet(isPresented: $show3105Settings) { SettingsView() }
            .sheet(isPresented: $show3105Logs) { LogView() }
            .patchStorePresentation(patchStore)
            .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
            .onAppear { appState.detectSupport() }
        .onChange(of: patchDraftCoordinator.request?.id) { _, id in if id != nil { section = 2 } }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { _, id in if id != nil { section = 2 } }
    }
}

struct NiK3105ToolsDashboardView: View {
    @AppStorage("nik.language") private var language = "vi"
    @StateObject private var systemFeatures = NiKSystemFeaturesStore()
    @State private var dialerPackages: [NiKDialerPackage] = []
    @State private var importingDialer = false
    @State private var cacheSummaryText = ""
    @State private var isScanningCache = false
    @State private var sharedPrefsItems: [URL] = []
    @State private var selectedInspectorFile: NiKPreviewDocument?
    @State private var statusBanner: String?

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                lockScreenAndSupervisedCard
                dialerAndWallpaperCard
                deepCleanerCard
                sharedPreferencesInspectorCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            dialerPackages = NiKDialerService.loadInstalledPackages()
        }
        .fileImporter(isPresented: $importingDialer, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let pkg = try NiKDialerService.importPackage(from: url)
                dialerPackages = NiKDialerService.loadInstalledPackages()
                statusBanner = t("Đã nạp gói Dialer: \(pkg.name) (\(pkg.items.count) phím)", "Loaded Dialer: \(pkg.name) (\(pkg.items.count) keys)")
            } catch {
                statusBanner = error.localizedDescription
            }
        }
        .sheet(item: $selectedInspectorFile) { doc in
            NiKQuickLook(url: doc.url)
        }
    }

    private var lockScreenAndSupervisedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                title: t("Footnote & Supervised", "Footnote & Supervised"),
                subtitle: t("Tuỳ chỉnh chữ cuối màn hình khóa và trạng thái giám sát thiết bị", "Customize lock screen footnote and supervised state"),
                icon: "lock.iphone",
                color: .cyan
            )

            TextField(t("Nội dung Footnote màn hình khóa...", "Lock screen footnote text..."), text: $systemFeatures.footnoteText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .font(.subheadline)

            Toggle(t("Bật chế độ Supervised (IsSupervised)", "Enable Supervised Mode"), isOn: $systemFeatures.isSupervisedEnabled)
                .font(.subheadline.weight(.medium))

            TextField(t("Tên tổ chức (OrganizationName)", "Organization Name"), text: $systemFeatures.organizationName)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .font(.subheadline)

            HStack(spacing: 10) {
                Button {
                    systemFeatures.applyFootnote()
                    statusBanner = systemFeatures.lastStatusMessage
                } label: {
                    Label(t("Lưu Footnote", "Apply Footnote"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button {
                    systemFeatures.applySupervisedState()
                    statusBanner = systemFeatures.lastStatusMessage
                } label: {
                    Label(t("Lưu Supervised", "Apply Supervised"), systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Button(role: .destructive) {
                    systemFeatures.restoreOriginalSystemConfigs()
                    statusBanner = systemFeatures.lastStatusMessage
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if let statusBanner, !statusBanner.isEmpty {
                Text(statusBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dialerAndWallpaperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                title: t("Dialer (.3105pass) & Hình nền (.tendies)", "Dialer (.3105pass) & Wallpapers"),
                subtitle: t("Thay bàn phím quay số Sáng/Tối/Đậm một chạm và quản lý gói hình nền", "One-tap keypad theming and .tendies wallpaper installer"),
                icon: "circle.grid.3x3.fill",
                color: .purple
            )

            HStack(spacing: 10) {
                Button {
                    importingDialer = true
                } label: {
                    Label(t("Nhập .3105pass", "Import .3105pass"), systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    if let pkg = try? NiKDialerService.createSamplePackage() {
                        dialerPackages = NiKDialerService.loadInstalledPackages()
                        statusBanner = t("Đã tạo mẫu: \(pkg.name)", "Created sample: \(pkg.name)")
                    }
                } label: {
                    Label(t("Tạo mẫu", "Sample"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    WallpaperLabView()
                } label: {
                    Label(t("Hình nền", "Wallpapers"), systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if !dialerPackages.isEmpty {
                ForEach(dialerPackages.prefix(3)) { pkg in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pkg.name).font(.subheadline.weight(.semibold))
                            Text("\(pkg.items.count) phím · \(pkg.detectedStyles.map(\.rawValue).joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(t("Áp dụng", "Apply")) {
                            do { statusBanner = try NiKDialerService.apply(pkg) }
                            catch { statusBanner = error.localizedDescription }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button(t("Khôi phục", "Restore")) {
                            do { statusBanner = try NiKDialerService.restore(pkg) }
                            catch { statusBanner = error.localizedDescription }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deepCleanerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                title: t("Dọn dẹp sâu Cache / Temp / Logs", "Deep Cache / Temp / Logs Cleaner"),
                subtitle: cacheSummaryText.isEmpty ? t("Chưa quét dung lượng Cache / Temp", "Cache / Temp not scanned yet") : cacheSummaryText,
                icon: "sparkles.rectangle.stack.fill",
                color: .green
            )

            HStack(spacing: 10) {
                Button {
                    scanCaches()
                } label: {
                    if isScanningCache {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(t("Quét dung lượng", "Scan Size"), systemImage: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isScanningCache)

                Button {
                    cleanCachesNow()
                } label: {
                    Label(t("Dọn nhanh 1 chạm", "Quick Clean"), systemImage: "trash.slash.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                NavigationLink {
                    CleanerView()
                } label: {
                    Label(t("Chi tiết", "Details"), systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sharedPreferencesInspectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(
                title: t("Quét & Sửa nhanh Shared Preferences", "Shared Preferences & AppGroup Inspector"),
                subtitle: t("Tìm nhanh cấu hình .plist trong AppGroup / Application (RevenueCat, Trial, Cấu hình) và sửa trực tiếp", "Scan AppGroup & Application .plist files and edit inline"),
                icon: "slider.horizontal.below.square.and.square.filled",
                color: .orange
            )

            HStack(spacing: 10) {
                Button {
                    scanSharedPreferences()
                } label: {
                    Label(t("Quét Plist cấu hình", "Scan Plists"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                NavigationLink {
                    NiK3105V2HubView()
                } label: {
                    Label(t("Patch Workspace v9", "Workspace v9"), systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if !sharedPrefsItems.isEmpty {
                VStack(spacing: 6) {
                    ForEach(sharedPrefsItems.prefix(8), id: \.path) { url in
                        Button {
                            selectedInspectorFile = NiKPreviewDocument(url: url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.gearshape.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func cardHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func scanCaches() {
        guard !isScanningCache else { return }
        isScanningCache = true
        Task {
            let summary = await Task.detached(priority: .userInitiated) { Self.cacheSummary() }.value
            let formatted = ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file)
            cacheSummaryText = t("Đã quét \(summary.apps) ứng dụng · Có thể dọn: \(formatted)", "Scanned \(summary.apps) apps · Reclaimable: \(formatted)")
            isScanningCache = false
        }
    }

    nonisolated private static func cacheSummary() -> (bytes: Int64, apps: Int) {
        let apps = ContainerStore.installedAppsFromAPI()
        var totalBytes: Int64 = 0
        var appCount = 0
        let fm = FileManager.default
        for app in apps where !app.containerPath.isEmpty {
            var appHasCache = false
            for sub in ["Library/Caches", "tmp", "Library/Logs"] {
                let dir = URL(fileURLWithPath: app.containerPath).appendingPathComponent(sub)
                if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                    for case let fileURL as URL in enumerator {
                        if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
                            totalBytes += Int64(values.fileSize ?? 0)
                            appHasCache = true
                        }
                    }
                }
            }
            if appHasCache { appCount += 1 }
        }
        return (totalBytes, appCount)
    }

    private func cleanCachesNow() {
        isScanningCache = true
        Task.detached(priority: .userInitiated) {
            let apps = ContainerStore.installedAppsFromAPI()
            var removedBytes: Int64 = 0
            let fm = FileManager.default
            for app in apps where !app.containerPath.isEmpty {
                for sub in ["Library/Caches", "tmp", "Library/Logs"] {
                    let dir = URL(fileURLWithPath: app.containerPath).appendingPathComponent(sub)
                    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
                    for item in items {
                        let size = Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        if (try? fm.removeItem(at: item)) != nil {
                            removedBytes += size
                        }
                    }
                }
            }
            let formatted = ByteCountFormatter.string(fromByteCount: removedBytes, countStyle: .file)
            await MainActor.run {
                cacheSummaryText = t("Đã giải phóng \(formatted) bộ nhớ đệm & tệp tạm.", "Freed \(formatted) of cache and temporary files.")
                isScanningCache = false
            }
        }
    }

    private func scanSharedPreferences() {
        Task.detached(priority: .userInitiated) {
            var found: [URL] = []
            let fm = FileManager.default
            let roots = [
                "/private/var/mobile/Containers/Shared/AppGroup",
                "/private/var/mobile/Containers/Data/Application"
            ]
            for root in roots {
                guard let containers = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for uuid in containers.prefix(120) {
                    let prefsPath = (root as NSString).appendingPathComponent("\(uuid)/Library/Preferences")
                    guard let files = try? fm.contentsOfDirectory(atPath: prefsPath) else { continue }
                    for file in files where file.lowercased().hasSuffix(".plist") {
                        let fullURL = URL(fileURLWithPath: (prefsPath as NSString).appendingPathComponent(file))
                        let lower = file.lowercased()
                        if lower.contains("revenuecat") || lower.contains("group.") || lower.contains("locket") || !lower.hasPrefix("com.apple.") {
                            found.append(fullURL)
                        }
                    }
                }
            }
            let sorted = found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            await MainActor.run {
                sharedPrefsItems = sorted
                statusBanner = sorted.isEmpty
                    ? t("Chưa tìm thấy tệp Preferences nào (kiểm tra quyền truy cập container).", "No Preferences files found (check container access).")
                    : t("Tìm thấy \(sorted.count) tệp Preferences. Chạm vào tệp để xem trước.", "Found \(sorted.count) Preferences files. Tap a file to preview.")
            }
        }
    }
}

struct NiKHexViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var info = ""
    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6) }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding()
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { loadHex() }
        }
    }
    private func loadHex() {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let maxBytes = 65536
            let data = try handle.read(upToCount: maxBytes) ?? Data()
            let total = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? Int64(data.count)
            info = total > Int64(maxBytes) ? "Hiển thị \(maxBytes) / \(total) bytes đầu tiên" : "Tổng: \(total) bytes"
            let bytes = [UInt8](data)
            var out: [String] = []
            for offset in stride(from: 0, to: bytes.count, by: 16) {
                let end = min(offset + 16, bytes.count)
                let chunk = bytes[offset..<end]
                let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
                let pad = String(repeating: "   ", count: max(0, 16 - chunk.count))
                let ascii = chunk.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
                out.append(String(format: "%08X  ", offset) + hex + pad + "  |" + ascii + "|")
            }
            lines = out.isEmpty ? ["(Tệp trống)"] : out
        } catch {
            info = error.localizedDescription
            lines = []
        }
    }
}

struct NiKFileItem: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date
    var id: String { url.path }
}
typealias NiKFilesSort = NiKFileBrowserSort
struct NiKShareItem: Identifiable { let id = UUID(); let url: URL }
struct NiKFolderTarget: Identifiable { let id = UUID(); let item: NiKFileItem; let isCopy: Bool }
struct NiKShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct NiKFolderPickerSheet: View {
    let item: NiKFileItem
    let isCopy: Bool
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            NiKFolderDestination(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], item: item, isCopy: isCopy) {
                onComplete()
                dismiss()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
        }
    }
}
private struct NiKFolderDestination: View {
    let directory: URL
    let item: NiKFileItem
    let isCopy: Bool
    let onComplete: () -> Void
    @State private var folders: [URL] = []
    @State private var errorMessage: String?
    @State private var busy = false
    var body: some View {
        List {
            Button(isCopy ? "Sao chép vào đây" : "Di chuyển vào đây") {
                busy = true
                Task {
                    do {
                        let source = item.url, destination = directory, copy = isCopy
                        let target = try NiKFileOperations.child(named: source.lastPathComponent, in: destination)
                        let lease = try NiKManagedFileAccess.reserve(copy ? [target] : [source, target])
                        defer { NiKFileMutationReservations.shared.release(lease) }
                        try await Task.detached { try NiKFileOperations.transfer(source, into: destination, copy: copy) }.value
                        onComplete()
                    } catch { errorMessage = error.localizedDescription }
                    busy = false
                }
            }
            if busy { ProgressView() }
            ForEach(folders, id: \.self) { folder in
                NavigationLink(folder.lastPathComponent) {
                    NiKFolderDestination(directory: folder, item: item, isCopy: isCopy, onComplete: onComplete)
                }
            }
        }
        .disabled(busy)
        .navigationTitle(directory.lastPathComponent)
        .task {
            do {
                folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter {
                    let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    return values.isDirectory == true && values.isSymbolicLink != true && $0 != item.url
                }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Không thực hiện được", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

extension NiKLibraryItem {
    var ipaURL: URL { NiKLibrary.root.appendingPathComponent(filename) }
    var size: Int64 { Int64((try? ipaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    var iconURL: URL? {
        let url = NiKLibrary.root.appendingPathComponent(filename + ".png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
struct NiKAppIcon: View {
    let url: URL?
    let size: CGFloat
    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().padding(10).foregroundStyle(.cyan)
                    .background(Color.cyan.opacity(0.12))
            }
        }.frame(width: size, height: size)
    }
}

/// Lifetime follows the import form, including picker presentations. User originals are never owned.
final class NiKTemporaryFiles: ObservableObject {
    private var directories: [URL] = []
    func retain(_ directory: URL) { directories.append(directory) }
    func copy(_ source: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nikcert-" + UUID().uuidString)
        directories.append(directory)
        return try NiKFileImport.copy(source, into: directory)
    }
    func clear() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        directories.removeAll()
    }
    deinit { clear() }
}
