import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation


struct NiKInspectView: View { 
    var initialURL: URL? = nil
    @State private var importing = false
    @State private var report = "Chọn Mach-O/dylib, .deb/.ar tên ngắn hoặc .tar để xem thông tin. Tối đa 16 MB; không thay đổi tệp."
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("Chọn tệp để kiểm tra") { importing = true }.disabled(busy)
                if busy { ProgressView() }
                Text(report).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Kiểm tra tệp")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get()
               Task { await inspect(url: url) }
            } catch { report = error.localizedDescription }
        } 
        .task { if let url = initialURL { await inspect(url: url) } }
    } 
    private func inspect(url: URL) async {
busy = true
report = await Task.detached(priority: .userInitiated) {
let accessed = url.startAccessingSecurityScopedResource()
defer { if accessed { url.stopAccessingSecurityScopedResource() } }
do { return try Self.inspectFile(at: url) }
catch { return error.localizedDescription }
}.value
busy = false
    }
    private static func inspectFile(at url: URL) throws -> String {
        if url.pathExtension.lowercased() == "ipa" {
            return try inspectIPA(at: url)
        }
        return try NiKArchiveInspector.report(at: url)
    }

    private static func inspectIPA(at url: URL) throws -> String {
        let archive = try Archive(url: url, accessMode: .read)
        var infoPlist: [String: Any] = [:]
        var frameworks = Set<String>()
        var dylibs = Set<String>()
        var plugins = Set<String>()

        for entry in archive {
            let parts = entry.path.split(separator: "/").map(String.init)
            guard parts.count >= 3, parts[0] == "Payload", parts[1].hasSuffix(".app") else { continue }
            if parts.count == 3, parts[2] == "Info.plist" {
                var data = Data()
                guard entry.uncompressedSize <= 1_048_576 else { throw NiKError("Info.plist vượt 1 MB.") }
                let crc = try archive.extract(entry) { chunk in
                    guard data.count + chunk.count <= 1_048_576 else { throw NiKError("Info.plist vượt 1 MB.") }
                    data.append(chunk)
                }
                guard crc == entry.checksum else { throw NiKError("Info.plist lỗi CRC.") }
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    infoPlist = plist
                }
            } else if parts[2] == "Frameworks", parts.count >= 4 {
                frameworks.insert(parts[3])
            } else if parts[2] == "PlugIns", parts.count >= 4 {
                plugins.insert(parts[3])
            }
            if entry.path.lowercased().hasSuffix(".dylib") {
                dylibs.insert(parts.last ?? entry.path)
            }
        }

        var lines: [String] = ["IPA: \(url.lastPathComponent)"]
        let bundleName = (infoPlist["CFBundleDisplayName"] as? String) ?? (infoPlist["CFBundleName"] as? String) ?? "-"
        let bundleID = (infoPlist["CFBundleIdentifier"] as? String) ?? "-"
        let version = (infoPlist["CFBundleShortVersionString"] as? String) ?? "-"
        let build = (infoPlist["CFBundleVersion"] as? String) ?? "-"
        let executable = (infoPlist["CFBundleExecutable"] as? String) ?? "-"
        let minOS = (infoPlist["MinimumOSVersion"] as? String) ?? "-"
        lines.append("Info.plist:")
        lines.append("  Name: \(bundleName)")
        lines.append("  Bundle ID: \(bundleID)")
        lines.append("  Version: \(version) (\(build))")
        lines.append("  Executable: \(executable)")
        lines.append("  MinimumOSVersion: \(minOS)")
        lines.append("Frameworks (\(frameworks.count)):")
        lines.append(contentsOf: frameworks.sorted().map { "  - \($0)" })
        lines.append("Dylibs (\(dylibs.count)):")
        lines.append(contentsOf: dylibs.sorted().map { "  - \($0)" })
        lines.append("PlugIns (\(plugins.count)):")
        lines.append(contentsOf: plugins.sorted().map { "  - \($0)" })
        return lines.joined(separator: "\n")
    }
}
