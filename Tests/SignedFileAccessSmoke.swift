import Foundation
@main struct SignedFileAccessSmoke {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let signed = root.appendingPathComponent("Signed")
        try fm.createDirectory(at: signed, withIntermediateDirectories: false)
        let file = signed.appendingPathComponent("test.ipa")
        try Data([1]).write(to: file)
        precondition(NiKSignedFileAccess.available(file.path, directory: signed) != nil)
        let link = signed.appendingPathComponent("alias.ipa")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(NiKSignedFileAccess.available(link.path, directory: signed) == nil)
        let outside = root.appendingPathComponent("outside.ipa"); try Data([1]).write(to: outside)
        precondition(NiKSignedFileAccess.available(outside.path, directory: signed) == nil)
        try fm.removeItem(at: file)
        precondition(NiKSignedFileAccess.available(file.path, directory: signed) == nil)
        print("PASS: signed file presence, missing/deleted output, symlink and outside-directory rejection")
    }
}
