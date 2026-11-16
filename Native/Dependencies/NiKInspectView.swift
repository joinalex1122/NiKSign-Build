import SwiftUI
import UniformTypeIdentifiers

struct NiKInspectView: View {
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
                busy = true
                Task {
                    let result = await Task.detached(priority: .userInitiated) { () -> String in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        do { return try NiKArchiveInspector.report(at: url) }
                        catch { return error.localizedDescription }
                    }.value
                    report = result; busy = false
                }
            } catch { report = error.localizedDescription }
        }
    }
}
