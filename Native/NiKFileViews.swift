import SwiftUI
import UIKit

struct NiKHubPreview: View {
    @State private var section = 2
    @State private var session = FilesTabSession()
    var body: some View {
        NavigationStack {
            VStack {
                Picker("Nhóm", selection: $section) { Text("Dự án").tag(0); Text("Ứng dụng").tag(1); Text("Công cụ").tag(2) }.pickerStyle(.segmented).padding()
                if section == 0 { PatchProjectsView() }
                else if section == 1 { AppDataBrowserView(tabSession: $session) }
                else {
                    List {
                        NavigationLink("Wallpaper · Hình nền") { WallpaperLabView() }
                        NavigationLink("Dialer · Footnote · Supervised") { NiK3105V2HubView() }
                        NavigationLink("Cleaner · Dọn dẹp") { CleanerView() }
                        NavigationLink("Nguồn & công cụ 3105 gốc") { ContentView() }
                        Text("Khả năng sử dụng tùy thuộc thiết bị. Các công cụ chuyên sâu dùng bộ xử lý 3105 hiện có.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("3105")
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
enum NiKFilesSort { case name, date, size }
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
