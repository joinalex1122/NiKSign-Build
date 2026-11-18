import SwiftUI

struct NiKTrashView: View {
    @ObservedObject private var trash = NiKTrashController.shared
    @AppStorage("nik.language") private var language = "vi"
    @State private var purgeTarget: NiKTrashRecord?
    @State private var confirmClear = false
    @State private var hasLoaded = false
    @State private var shareItem: NiKShareItem?
    @StateObject private var temporaryFiles = NiKTemporaryFiles()
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var active: [NiKTrashRecord] { trash.records.filter { ![.purged, .restored, .aborted].contains($0.state) } }
    private var finished: [NiKTrashRecord] { trash.records.filter { [.purged, .restored, .aborted].contains($0.state) } }
    var body: some View {
        List {
            Section {
                Text(t("Thùng rác giữ bản gốc trong phạm vi NiKSign, tối đa 4 GB. Khôi phục không ghi đè tệp mới. Xóa vĩnh viễn cần xác nhận riêng.", "Trash keeps NiKSign-managed originals up to 4 GB. Restore never overwrites a new file. Permanent deletion requires separate confirmation."))
                    .font(.footnote).foregroundStyle(.secondary)
                if trash.busy || !hasLoaded { ProgressView() }
                if hasLoaded && !trash.storageAvailable {
                    Text(t("Chưa mở được dữ liệu thùng rác. Nhật ký được giữ nguyên để kiểm tra.", "Trash data is unavailable. The journal is preserved for review.")).font(.footnote).foregroundStyle(.orange)
                    ShareLink(t("Xuất journal để khôi phục", "Export Recovery Journal"), item: trash.recoveryIndexURL)
                }
            }
            Section(t("Mục đang giữ", "Retained Items")) {
                if hasLoaded && active.isEmpty && trash.storageAvailable { Text(t("Thùng rác trống", "Trash Is Empty")).foregroundStyle(.secondary) }
                ForEach(active) { record in row(record) }
            }
            if !finished.isEmpty {
                Section(t("Lịch sử", "History")) {
                    ForEach(finished) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.original.components.last ?? "File")
                            Text(stateText(record.state)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(t("Thùng rác", "Trash"))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(t("Kiểm tra lại", "Recheck")) { Task { await trash.refresh() } }
                    Button(t("Dọn lịch sử đã kết thúc", "Clear Finished History")) { confirmClear = true }.disabled(finished.isEmpty || trash.busy)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await trash.refresh(); hasLoaded = true }
        .refreshable { await trash.refresh(); hasLoaded = true }
        .confirmationDialog(t("Xóa vĩnh viễn bản sao này?", "Permanently Delete This Backup?"), isPresented: Binding(get: { purgeTarget != nil }, set: { if !$0 { purgeTarget = nil } })) {
            if let record = purgeTarget {
                Button(t("Xóa vĩnh viễn", "Delete Permanently"), role: .destructive) {
                    purgeTarget = nil
                    Task { await trash.purge(record.id, confirmingPermanentDeletion: true) }
                }
            }
            Button(t("Hủy", "Cancel"), role: .cancel) { purgeTarget = nil }
        } message: { Text(t("Dữ liệu backup bị xóa sẽ không khôi phục được bằng NiKSign. Tệp mới ở vị trí gốc được giữ nguyên.", "Deleted backup data cannot be restored by NiKSign. A new file at the original location is preserved.")) }
        .confirmationDialog(t("Dọn lịch sử đã kết thúc?", "Clear Finished History?"), isPresented: $confirmClear) {
            Button(t("Dọn lịch sử", "Clear History")) { Task { await trash.clearFinished() } }
            Button(t("Hủy", "Cancel"), role: .cancel) {}
        } message: { Text(t("Chỉ xóa bản ghi đã khôi phục, đã xóa vĩnh viễn hoặc đã hủy. Backup đang giữ không bị xóa.", "Only restored, permanently deleted or aborted records are cleared. Retained backups are preserved.")) }
        .alert(t("Thùng rác", "Trash"), isPresented: Binding(get: { trash.message != nil }, set: { if !$0 { trash.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(trash.message ?? "") }
        .sheet(item: $shareItem) { NiKShareSheet(items: [$0.url]) }
    }
    private func row(_ record: NiKTrashRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.original.components.last ?? "File").font(.headline)
            Text(record.original.components.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(stateText(record.state)).font(.caption).foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(record.bytes), countStyle: .file)).font(.caption2)
            if [.trashed, .trashedNeedsIndex, .restoredNeedsIndex].contains(record.state) {
                Button(t("Khôi phục / hoàn tất khôi phục", "Restore / Finish Restoration")) { Task { await trash.restore(record.id) } }.disabled(trash.busy)
            }
            if record.state == .trashedNeedsIndex {
                Button(t("Hoàn tất xóa khỏi thư viện", "Finish Removing from Library")) { Task { await trash.finishPendingRemoval(record.id) } }.disabled(trash.busy)
            }
            if [.needsReview, .missing, .trashPrepared, .restorePrepared].contains(record.state) {
                Button(t("Kiểm tra lại sau khi xử lý xung đột", "Recheck after Resolving the Conflict")) { Task { await trash.refresh() } }.disabled(trash.busy)
            }
            if record.state != .restoredNeedsIndex {
                Button(t("Xuất bản sao để kiểm tra", "Export Backup for Review")) { export(record.id) }.disabled(trash.busy)
            }
            if [.trashed, .purgePrepared, .needsReview, .missing].contains(record.state) {
                Button(t("Xóa vĩnh viễn…", "Delete Permanently…"), role: .destructive) { purgeTarget = record }.disabled(trash.busy)
            }
        }.padding(.vertical, 6)
    }
    private func export(_ id: UUID) {
        Task {
            do {
                let exported = try await trash.exportBackup(id)
                temporaryFiles.retain(exported.directory)
                shareItem = NiKShareItem(url: exported.url)
            } catch { trash.message = error.localizedDescription }
        }
    }
    private func stateText(_ state: NiKTrashRecord.State) -> String {
        switch state {
        case .trashPrepared: return t("Đang chờ xác minh di chuyển", "Move Verification Pending")
        case .trashedNeedsIndex: return t("Đã giữ bản gốc; cập nhật thư viện còn chờ", "Original Retained; Library Update Pending")
        case .trashed: return t("Đang giữ trong Thùng rác", "Retained in Trash")
        case .restorePrepared: return t("Khôi phục đang chờ xác minh", "Restore Verification Pending")
        case .restoredNeedsIndex: return t("Tệp đã trở lại; metadata thư viện còn chờ", "File Restored; Library Metadata Pending")
        case .restored: return t("Đã khôi phục", "Restored")
        case .purgePrepared: return t("Xóa vĩnh viễn chưa hoàn tất; backup có thể thiếu", "Permanent Deletion Incomplete; Backup May Be Partial")
        case .purged: return t("Đã xóa vĩnh viễn backup", "Backup Permanently Deleted")
        case .aborted: return t("Đã hủy trước di chuyển", "Aborted before Moving")
        case .missing: return t("Thiếu dữ liệu; cần kiểm tra", "Data Missing; Review Required")
        case .needsReview: return t("Có xung đột hoặc dữ liệu thay đổi; cần kiểm tra", "Conflict or Data Changed; Review Required")
        }
    }
}
