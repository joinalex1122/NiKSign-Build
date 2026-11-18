import Foundation

enum NiK3105AccessAssessment {
    enum Stage: Equatable { case unknownEntitlements, missingAppGroup, inaccessibleAppGroup, missingBackend, candidate }
    static func stage(groups: [String]?, accessible: Set<String>, backendAvailable: Bool) -> Stage {
        guard let groups else { return .unknownEntitlements }
        guard !groups.isEmpty else { return .missingAppGroup }
        guard groups.contains(where: accessible.contains) else { return .inaccessibleAppGroup }
        return backendAvailable ? .candidate : .missingBackend
    }
}
