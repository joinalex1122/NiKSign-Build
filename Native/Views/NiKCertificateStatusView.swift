import SwiftUI

struct NiKCertificateStatusView: View {
    let profile: NiKCertificateProfile
    @ObservedObject var store: NiKCertificateStore
    @AppStorage("nik.language") private var language = "vi"
    @State private var error: String?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = profile.freshRevocationStatus(at: context.date)
            let seconds = profile.remainingSeconds(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                if let seconds {
                    if seconds == 0 {
                        Text(t("Đã hết hạn", "Expired")).foregroundStyle(.red)
                    } else {
                        let hours = Int(ceil(seconds / 3600))
                        Text(t("Còn \(hours / 24) ngày \(hours % 24) giờ", "\(hours / 24) days \(hours % 24) hours remaining"))
                        Text(t("Tính theo hạn sớm hơn của chứng chỉ và profile.", "Uses the earlier certificate/profile expiry."))
                            .foregroundStyle(.secondary)
                    }
                    if profile.certificateExpirationDate == nil || profile.expirationDate == nil {
                        Text(t("Thiếu một mốc hạn; nhập lại chứng chỉ/profile để bổ sung.", "One expiry is missing; reimport the certificate/profile to complete it."))
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text(t("Chưa xác định hạn", "Expiry unknown")).foregroundStyle(.secondary)
                }
                Text(status == .revoked ? t("Đã thu hồi", "Revoked") : status == .good ? (seconds == 0 ? t("OCSP đạt · đã hết hạn", "OCSP passed · expired") : t("Tốt · kiểm tra OCSP đạt", "Good · OCSP check passed")) : t("Chưa xác minh thu hồi", "Revocation unverified"))
                    .foregroundStyle(status == .revoked ? Color.red : status == .good ? Color.green : Color.secondary)
                if let date = profile.revocationCheckedAt {
                    Text(t("Lần kiểm tra: ", "Last check: ") + date.formatted()).foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        do { try await store.checkRevocation(profile); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    if store.revocationChecks.contains(profile.id) { ProgressView() }
                    else { Text(t("Kiểm tra thu hồi trực tuyến", "Check revocation online")) }
                }
                .disabled(store.revocationChecks.contains(profile.id))
                if let error { Text(error).foregroundStyle(.red) }
            }.font(.caption)
        }
    }
}
