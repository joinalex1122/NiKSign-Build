import SwiftUI
import UIKit

struct NiKDiagnosticsView: View {
    @ObservedObject private var queue = NiKSigningQueue.shared
    @ObservedObject private var recovery = NiKRecoveryController.shared
    @AppStorage("nik.language") private var language = "vi"
    @State private var report: String?
    @State private var exportURL: URL?
    @State private var busy = false
    @State private var error: String?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    var body: some View {
        List {
            Section {
                Text(t("Báo cáo chỉ chứa phiên bản, số lượng và trạng thái thao tác. Không đưa tên tệp/app/chứng chỉ, đường dẫn, URL, UDID, mật khẩu hoặc lỗi thô vào bản xuất.",
                       "The report contains versions, counts and operation states only. File/app/certificate names, paths, URLs, UDIDs, passwords and raw errors are excluded."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(t("Tạo lại báo cáo", "Regenerate Report")) { generate() }.disabled(busy)
                if busy { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if let exportURL {
                    ShareLink(item: exportURL) { Label(t("Xuất báo cáo JSON", "Export JSON Report"), systemImage: "square.and.arrow.up") }
                }
            }
            if let report {
                Section(t("Nội dung sẽ xuất", "Export Preview")) {
                    Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(t("Chẩn đoán", "Diagnostics"))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .task { if report == nil { generate() } }
    }
    private func generate() {
        guard !busy else { return }
        busy = true; error = nil; exportURL = nil
        Task {
            defer { busy = false }
            await recovery.refresh()
            let jobs = queue.jobs, records = recovery.records
            let signingAvailable = queue.storageAvailable, recoveryAvailable = recovery.storageAvailable
            let certificateAvailable = NiKCertificateStore.shared.loadFailure == nil
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
            let system = UIDevice.current.systemVersion
            do {
                let result = try await Task.detached {
                    let data = try NiKDiagnosticReport.make(jobs: jobs, recovery: records,
                        appVersion: version, appBuild: build, systemVersion: system,
                        signingStorageAvailable: signingAvailable, recoveryStorageAvailable: recoveryAvailable, certificateStorageAvailable: certificateAvailable).encoded()
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NiKSign-Diagnostics", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent(UUID().uuidString + ".json")
                    try data.write(to: url, options: .atomic)
                    return (String(decoding: data, as: UTF8.self), url)
                }.value
                report = result.0; exportURL = result.1
            } catch { self.error = error.localizedDescription }
        }
    }
}
