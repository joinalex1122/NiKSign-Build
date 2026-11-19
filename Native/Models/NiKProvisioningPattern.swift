import Foundation

enum NiKProvisioningPattern {
    static func matches(pattern: String, bundleID: String) -> Bool {
        guard !pattern.isEmpty, !bundleID.isEmpty, !bundleID.contains("*") else { return false }
        if pattern.hasSuffix("*") {
            let prefix = pattern.dropLast()
            return !prefix.contains("*") && bundleID.hasPrefix(prefix) && bundleID.count > prefix.count
        }
        return pattern == bundleID
    }
}
