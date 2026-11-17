import Foundation

enum NiKDistributionKind: String, Codable, Sendable {
    case development, adHoc, enterprise, appStore, unknown
}

struct NiKCertificateAssessment: Sendable {
    struct Issue: Identifiable, Sendable {
        enum Severity: String, Sendable { case blocking, warning }
        let code: String
        let severity: Severity
        let vi: String
        let en: String
        var id: String { code }
    }
    let distribution: NiKDistributionKind
    let issues: [Issue]
    var canSign: Bool { !issues.contains { $0.severity == .blocking } }
}

enum NiKCertificateCompatibility {
    static func bundleMatches(pattern: String, bundleID: String) -> Bool {
        guard !pattern.isEmpty, !bundleID.isEmpty, !bundleID.contains("*") else { return false }
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast())
            return bundleID.hasPrefix(prefix) && bundleID.count > prefix.count && !bundleID.contains("*")
        }
        return !pattern.contains("*") && pattern == bundleID
    }

    static func assess(_ profile: NiKCertificateProfile, bundleID: String?, deviceUDID: String? = nil, now: Date = Date(), allowMismatch: Bool = false) -> NiKCertificateAssessment {
        var issues: [NiKCertificateAssessment.Issue] = []
        func add(_ code: String, _ blocking: Bool, _ vi: String, _ en: String) {
            issues.append(.init(code: code, severity: blocking ? .blocking : .warning, vi: vi, en: en))
        }
        if profile.teamID.isEmpty { add("team.missing", true, "Profile thiếu Team ID.", "The profile has no Team ID.") }
        if let expiry = profile.expirationDate {
            if expiry <= now { add("profile.expired", true, "Hồ sơ provisioning đã hết hạn.", "The provisioning profile has expired.") }
        } else { add("profile.expiry.unknown", false, "Không xác định được hạn provisioning.", "Provisioning expiry is unknown.") }
        if let expiry = profile.certificateExpirationDate {
            if expiry <= now { add("certificate.expired", true, "Chứng chỉ ký đã hết hạn.", "The signing certificate has expired.") }
        } else { add("certificate.expiry.unknown", false, "Cần kiểm tra hạn chứng chỉ khi ký (bản lưu cũ có thể thiếu dữ liệu).", "Certificate expiry must be checked during signing; older records may lack this field.") }
        if let start = profile.certificateCreationDate, start > now {
            add("certificate.notYetValid", true, "Chứng chỉ chưa đến ngày có hiệu lực.", "The certificate is not valid yet.")
        }
        if !profile.certMatchesProvision {
            add("certificate.mismatch", !allowMismatch, "Chứng chỉ không khớp với profile.", "The certificate does not match the profile.")
        }
        if profile.bundleIDPattern.isEmpty {
            add("profile.appID.missing", true, "Profile thiếu Application Identifier.", "The profile has no Application Identifier.")
        }
        if let bundleID {
            if !bundleMatches(pattern: profile.bundleIDPattern, bundleID: bundleID) {
                add("bundle.mismatch", true, "Bundle ID không được profile cho phép.", "The profile does not permit this Bundle ID.")
            }
        } else {
            add("bundle.unknown", false, "Chưa chọn IPA; chưa kiểm tra Bundle ID của ứng dụng.", "No IPA selected; its Bundle ID has not been checked.")
        }
        if let created = profile.creationDate, created > now {
            add("profile.notYetValid", true, "Provisioning chưa đến ngày có hiệu lực.", "The provisioning profile is not valid yet.")
        }
        let kind: NiKDistributionKind
        if profile.provisionsAllDevices == true { kind = .enterprise }
        else if profile.allowsDebugging == true { kind = .development }
        else if !profile.provisionedUDIDs.isEmpty { kind = .adHoc }
        else if profile.provisionsAllDevices == false { kind = .appStore }
        else { kind = .unknown }
        if kind == .appStore {
            add("distribution.appStore", false, "Profile App Store không xác nhận khả năng cài trực tiếp/OTA trên thiết bị.", "An App Store profile does not establish eligibility for direct/OTA installation.")
        }
        let udid = deviceUDID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if kind == .development || kind == .adHoc {
            if udid.isEmpty {
                add("device.unknown", false, "Chưa nhập UDID; chưa kiểm tra được thiết bị có trong profile.", "No UDID supplied; device membership has not been checked.")
            } else if !profile.provisionedUDIDs.contains(where: { $0.caseInsensitiveCompare(udid) == .orderedSame }) {
                add("device.notProvisioned", true, "UDID này không có trong provisioning profile.", "This UDID is absent from the provisioning profile.")
            }
        }
        return .init(distribution: kind, issues: issues)
    }
}
