import SwiftUI

struct NiKSigningQueueView: View {
    @ObservedObject var queue: NiKSigningQueue
    @AppStorage("nik.language") private var language = "vi"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            Section {
                Text(t("Mỗi công việc giữ riêng tùy chọn và chứng chỉ khi thêm vào hàng đợi. Công việc bị gián đoạn cần được thử lại; NiKSign không tự ký lại sau khi mở app.", "Each job keeps its options and certificate snapshot. Interrupted jobs require retry; reopening the app does not automatically sign again."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(queue.jobs.reversed()) { job in row(job) }
            if queue.jobs.isEmpty { Text(t("Chưa có công việc", "No Jobs Yet")) }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .navigationTitle(t("Hàng đợi ký", "Signing Queue"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(t("Chạy mục đang chờ", "Run Queued Jobs")) { queue.start() }
                    Button(t("Dọn lịch sử đã kết thúc", "Clear Finished History")) { queue.clearFinished() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert(t("Thông báo công việc", "Job Notice"), isPresented: Binding(get: { queue.message != nil }, set: { if !$0 { queue.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(queue.message ?? "") }
    }

    private func row(_ job: NiKSigningJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.title).font(.headline)
            Text(stateText(job.state)).font(.caption).foregroundStyle(.secondary)
            if !job.step.isEmpty { Text(job.step).font(.caption) }
            if job.state.isActive { ProgressView(value: job.fraction) }
            if let error = job.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if queue.cancellationRequests.contains(job.id) {
                Text(t("Đang chờ bộ ký tới điểm hủy an toàn…", "Waiting for the signer to reach a safe cancellation boundary…")).font(.caption)
            } else if !job.state.isTerminal {
                Button(t("Hủy công việc", "Cancel Job"), role: .destructive) { queue.cancel(job.id) }
            }
            if [.failed, .cancelled, .interrupted].contains(job.state) {
                Button(t("Thử lại từ bản gốc", "Retry from Original")) { queue.retry(job.id) }
            }
            if let output = job.output {
                ShareLink(item: output.ipaURL) { Label(t("Xuất kết quả", "Export Result"), systemImage: "square.and.arrow.up") }
            }
        }.padding(.vertical, 6)
    }
    private func stateText(_ state: NiKSigningJobState) -> String {
        switch state {
        case .queued: return t("Đang chờ", "Queued")
        case .checking: return t("Đang kiểm tra", "Checking")
        case .signing: return t("Đang ký", "Signing")
        case .packaging: return t("Đang đóng gói", "Packaging")
        case .succeeded: return t("Thành công", "Succeeded")
        case .failed: return t("Thất bại", "Failed")
        case .cancelled: return t("Đã hủy", "Cancelled")
        case .interrupted: return t("Bị gián đoạn", "Interrupted")
        }
    }
}

struct NiKBatchSigningView: View {
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @ObservedObject private var queue = NiKSigningQueue.shared
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""
    @AppStorage("nik.language") private var language = "vi"
    @State private var selected: Set<UUID> = []
    @State private var certificateChoice: UUID?
    @State private var notice: String?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            Section(t("Chứng chỉ cho IPA chưa chọn riêng", "Certificate for IPAs without an Override")) {
                Picker(t("Chứng chỉ", "Certificate"), selection: $certificateChoice) {
                    Text(t("Theo mặc định", "Use Default")).tag(nil as UUID?)
                    ForEach(certificates.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                Text(t("Chứng chỉ đã chọn riêng trong chi tiết từng IPA được ưu tiên.", "A certificate explicitly selected in an IPA's details takes priority.")).font(.caption)
            }
            Section(t("Chọn IPA", "Choose IPAs")) {
                ForEach(library.items) { item in
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    } label: {
                        HStack {
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
            Section {
                Button(t("Thêm vào hàng đợi và ký", "Queue and Sign")) { enqueue() }.disabled(selected.isEmpty)
                NavigationLink(t("Xem hàng đợi", "View Queue")) { NiKSigningQueueView(queue: queue) }
            }
        }
        .navigationTitle(t("Ký nhiều IPA", "Batch Signing"))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .alert(t("Thông báo", "Notice"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }
    private func enqueue() {
        do {
            let fallback = certificateChoice ?? UUID(uuidString: defaultCertificate) ?? certificates.selectedProfile?.id
            let jobs = try library.items.filter { selected.contains($0.id) }.map { item -> NiKSigningJob in
                guard let id = item.certificateID ?? fallback, certificates.profiles.contains(where: { $0.id == id }) else {
                    throw NiKError(item.title + ": " + t("Hãy chọn chứng chỉ hợp lệ.", "Choose an available certificate."))
                }
                return NiKSigningJob(libraryID: item.id, title: item.title, input: item.ipaURL, certificateID: id, options: item.options)
            }
            try queue.enqueue(jobs)
            notice = t("Đã thêm \(jobs.count) IPA. Mở hàng đợi để theo dõi.", "Queued \(jobs.count) IPAs. Open the queue to monitor progress.")
            selected.removeAll()
        } catch { notice = error.localizedDescription }
    }
}
