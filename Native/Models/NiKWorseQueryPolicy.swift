import Foundation

enum NiKWorseQueryPolicy {
    static func supports(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }
        if major == 26 { return minor < 7 || (minor == 7 && patch <= 2) }
        return major == 27 && (minor < 2 || (minor == 2 && patch == 0))
    }
    static func allowedPath(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.contains("\\") else { return nil }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let value = normalized.hasPrefix("/private/var/") ? String(normalized.dropFirst(8)) : normalized
        let roots = ["/var/mobile/Containers/Data/Application", "/var/mobile/Containers/Data/PluginKitPlugin",
                     "/var/mobile/Containers/Data/InternalDaemon", "/var/mobile/Containers/Shared/AppGroup",
                     "/var/containers/Data/System", "/var/containers/Shared/SystemGroup"]
        guard roots.contains(where: { value == $0 || value.hasPrefix($0 + "/") }) else { return nil }
        return normalized
    }
}
