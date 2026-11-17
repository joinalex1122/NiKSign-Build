import SwiftUI

struct NiKRecoveryHistoryView: View {
    @ObservedObject private var recovery = NiKRecoveryController.shared
    @AppStorage("nik.language") private var language = "vi"
    @State private var restoreID: UUID?
    @State private var discardID: UUID?
    @State private var share: NiKPreviewDocument?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            Section {
                Text(t("Backup được tạo trước khi sửa tệp, tối đa 32 MB/tệp và 256 MB tổng. Khôi phục sẽ từ chối ghi đè thay đổi mới. Backup không tự bị xóa sau khi khôi phục.", "Backups precede file edits, limited to 32 MB per file and 256 MB total. Restore refuses to overwrite newer changes. Restored backups are retained until you delete them."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if recovery.records.isEmpty { Text(t("Chưa có bản sao lưu chỉnh sửa", "No Edit Backups Yet")) }
            ForEach(recovery.records.reversed()) { record in row(record) }
        }
        .navigationTitle(t("Khôi phục tệp", "File Recovery"))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .task { await recovery.refresh() }
        .refreshable { await recovery.refresh() }
        .overlay { if recovery.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .confirmationDialog(t("Khôi phục nội dung gốc?", "Restore Original Contents?"), isPresented: Binding(get: { restoreID != nil }, set: { if !$0 { restoreID = nil } })) {
            if let id = restoreID { Button(t("Khôi phục", "Restore")) { Task { await recovery.restore(id) } } }
            Button(t("Hủy", "Cancel"), role: .cancel) { restoreID = nil }
        }
        .confirmationDialog(t("Xóa vĩnh viễn backup này?", "Permanently Delete This Backup?"), isPresented: Binding(get: { discardID != nil }, set: { if !$0 { discardID = nil } })) {
            if let id = discardID { Button(t("Xóa backup", "Delete Backup"), role: .destructive) { Task { await recovery.discard(id) } } }
            Button(t("Hủy", "Cancel"), role: .cancel) { discardID = nil }
        } message: { Text(t("Tệp đích giữ nguyên. Bạn sẽ mất khả năng khôi phục từ backup này.", "The current file is unchanged. You will lose restoration from this backup.")) }
        .sheet(item: $share) { NiKShareSheet(items: [$0.url]) }
        .alert(t("Khôi phục tệp", "File Recovery"), isPresented: Binding(get: { recovery.message != nil }, set: { if !$0 { recovery.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(recovery.message ?? "") }
    }
    private func row(_ record: NiKFileRecoveryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.target.lastPathComponent).font(.headline)
            Text(record.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
            Text(stateText(record.state)).font(.caption.weight(.semibold))
            Text(ByteCountFormatter.string(fromByteCount: Int64(record.originalSize), countStyle: .file)).font(.caption)
            if let message = record.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(t("Khôi phục", "Restore")) { restoreID = record.id }
                    .disabled(record.state == .restored || record.state == .aborted)
                Button(t("Xuất backup", "Export Backup")) {
                    Task {
                        do { share = NiKPreviewDocument(url: try await recovery.exportBackup(record.id)) }
                        catch { recovery.message = error.localizedDescription }
                    }
                }
                Button(role: .destructive) { discardID = record.id } label: { Image(systemName: "trash") }
            }.buttonStyle(.borderless).disabled(recovery.busy)
        }.padding(.vertical, 5)
    }
    private func stateText(_ state: NiKFileRecoveryRecord.State) -> String {
        switch state {
        case .prepared: return t("Đã sao lưu, chưa chốt thao tác", "Backed Up; Operation Pending")
        case .committed: return t("Đã chỉnh sửa", "Edited")
        case .aborted: return t("Đã hủy/hoàn tác thao tác", "Operation Aborted/Rolled Back")
        case .restored: return t("Đã khôi phục", "Restored")
        case .restoreFailed: return t("Chưa khôi phục được", "Restore Failed")
        case .needsReview: return t("Cần đối chiếu sau gián đoạn", "Review Required after Interruption")
        }
    }
}
