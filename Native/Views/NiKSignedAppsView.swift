import SwiftUI

struct NiKSignedAppsView: View {
    @AppStorage("nik.language") private var language = "vi"
    @Environment(\.scenePhase) private var scenePhase
    @State private var apps: [NiKSignedApp] = []
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var installTarget: NiKPreviewDocument?
    @State private var deleteTarget: NiKSignedApp?
    @State private var revision = UUID()
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var filtered: [NiKSignedApp] {
        apps.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(query) || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                Text(t("IPA trong Signed được giữ lại khi xóa hàng đợi ký. Chọn ứng dụng để cài hoặc mở menu để chia sẻ, xóa.", "IPAs in Signed remain after clearing the signing queue. Select an app to install, or open its menu to share or delete."))
                    .font(.footnote).foregroundStyle(.secondary)
                if loading { ProgressView(t("Đang đọc ứng dụng…", "Reading Applications…")) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            if apps.isEmpty && !loading {
                ContentUnavailableView(t("Chưa có ứng dụng đã ký", "No Signed Applications"), systemImage: "signature", description: Text(t("Ký IPA hoặc đặt IPA đã ký vào thư mục Signed.", "Sign an IPA or place a signed IPA in Signed.")))
            }
            ForEach(filtered) { app in
                VStack(alignment: .leading, spacing: 8) {
                    Button { installTarget = NiKPreviewDocument(url: app.url) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.title).font(.headline)
                            if let bundleID = app.bundleID { Text(bundleID + " · " + (app.version ?? "")).font(.caption).foregroundStyle(.secondary) }
                            Text(app.url.lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file) + " · " + app.modified.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(app.issue != nil)
                    if let issue = app.issue { Text(issue).font(.caption).foregroundStyle(.red) }
                    Menu {
                        Button(t("Cài đặt", "Install"), systemImage: "arrow.down.app") { installTarget = NiKPreviewDocument(url: app.url) }.disabled(app.issue != nil)
                        ShareLink(item: app.url) { Label(t("Chia sẻ IPA", "Share IPA"), systemImage: "square.and.arrow.up") }
                        Button(t("Chuyển vào thùng rác", "Move to Trash"), systemImage: "trash", role: .destructive) { deleteTarget = app }
                    } label: { Label(t("Tùy chọn", "Options"), systemImage: "ellipsis.circle") }
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle(t("Ứng dụng đã ký", "Signed Applications"))
        .searchable(text: $query, prompt: t("Tên ứng dụng hoặc Bundle ID", "Application Name or Bundle ID"))
        .toolbar { Button(t("Làm mới", "Refresh"), systemImage: "arrow.clockwise") { revision = UUID() } }
        .refreshable { await refresh() }
        .task(id: revision) { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { revision = UUID() } }
        .sheet(item: $installTarget) { NiKInstallIPAView(url: $0.url) }
        .confirmationDialog(t("Chuyển IPA vào thùng rác?", "Move IPA to Trash?"), isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            if let target = deleteTarget {
                Button(t("Chuyển vào thùng rác", "Move to Trash"), role: .destructive) {
                    deleteTarget = nil
                    Task {
                        do { try await NiKTrashController.shared.trash(target.url); revision = UUID() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            Button(t("Hủy", "Cancel"), role: .cancel) { deleteTarget = nil }
        } message: { Text(deleteTarget?.url.lastPathComponent ?? "") }
    }
    private func refresh() async {
        let request = UUID()
        // The task identity prevents a cancelled refresh from overwriting a newer result.
        refreshID = request
        loading = true; error = nil
        let worker = Task.detached { try NiKSignedApps.scan() }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            if refreshID == request { apps = result }
        } catch is CancellationError {} catch { if refreshID == request { self.error = error.localizedDescription } }
        if refreshID == request { loading = false }
    }
    @State private var refreshID = UUID()
}
