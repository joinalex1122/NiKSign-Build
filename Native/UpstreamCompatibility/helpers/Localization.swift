import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "nik.language"

    case english = "en"
    case vietnamese = "vi"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .simplifiedChinese: return "简体中文"
        }
    }

    func text(_ key: String) -> String {
        if key == "patch.error.unsupported_version" {
            switch self {
            case .vietnamese: return "NiKSign chưa hỗ trợ phiên bản hoặc tính năng trong gói này. Bộ nhập nhận schema 1–3 và nhóm schema 9 công khai chỉ thay thế tệp/thư mục trong ứng dụng; chưa nhận schema 9 có mật khẩu, App Group hoặc cấu hình động."
            case .english: return "NiKSign does not support this package version or feature. Imports support schema 1–3 and public schema 9 application file replacements/directories. Password-protected schema 9, App Groups and dynamic settings are not supported yet."
            case .simplifiedChinese: return "NiKSign 暂不支持此软件包版本或功能。支持 schema 1–3 和仅包含应用文件替换及目录的公开 schema 9；暂不支持加密 schema 9、App Group 或动态设置。"
            }
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    private var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

extension ExploitStatus {
    func displayText(language: AppLanguage) -> String {
        switch self {
        case .notStarted:
            return language.text("status.not_attempted")
        case .success(let method):
            let localizedMethod = method == "Simulator preview"
                ? language.text("method.simulator_preview")
                : method
            return language.text("status.ok_via", localizedMethod)
        case .failed(let method, let code):
            return language.text("status.failed_via", method, code)
        case .unsupported(let message):
            return language.text("status.unsupported_reason", message)
        }
    }
}
