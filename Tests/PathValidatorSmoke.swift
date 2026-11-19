import Foundation
@main struct PathValidatorSmoke {
    static func main() throws {
        let bundle = try NiKPathValidator.canonicalBundleIdentifier(" com.niksign.app ")
        precondition(bundle == "com.niksign.app")
        let path = try NiKPathValidator.canonicalRelativePath("Payload/Demo.app/Info.plist")
        precondition(path == "Payload/Demo.app/Info.plist")
        for raw in ["", "a", "a..b", "a.-b", "a.b-", "a.*", "a/b.c", "a.\n"] {
            do { _ = try NiKPathValidator.canonicalBundleIdentifier(raw); fatalError("Bad ID accepted") } catch {}
        }
        for raw in ["", "/a", "../a", "a/../b", "a//b", "a\\b", "a/./b", "a/\u{0}b"] {
            do { _ = try NiKPathValidator.canonicalRelativePath(raw); fatalError("Unsafe path accepted") } catch {}
        }
        print("PASS: independent IPA bundle/path validation and traversal rejection")
    }
}
