import Foundation

@main
struct CodecSmoke {
    static func main() throws {
        let rule = PatchRule(bundleID: "app.niksign.example", relativePath: "Documents/config.json",
                             replacementFilename: "config.json", replacementData: Data("{\"enabled\":true}".utf8))
        var project = PatchProject(name: "NiKSign Test", rules: [rule])
        let plain = try PatchPackageCodec.encodeNew(project: project, password: nil)
        assert(tryValue { try PatchPackageCodec.decode(plain.data, password: nil).project } == project)
        let protected = try PatchPackageCodec.encodeNew(project: project, password: "test-pass")
        expectFailure { _ = try PatchPackageCodec.decode(protected.data, password: "wrong") }
        let decoded = try PatchPackageCodec.decode(protected.data, password: "test-pass")
        project.name = "Edited"
        let updated = try PatchPackageCodec.update(protected.data, project: project, contentKey: decoded.contentKey)
        assert(tryValue { try PatchPackageCodec.decode(updated, password: "test-pass").project.name } == "Edited")
        expectFailure { _ = try PatchPackageCodec.decode(updated, password: nil) }
        var corrupt = protected.data; corrupt[corrupt.count - 10] ^= 0xff
        expectFailure { _ = try PatchPackageCodec.decode(corrupt, password: "test-pass") }
        for path in ["../secret", "/etc/config", "Library/../secret", "Library\\secret"] {
            expectFailure { _ = try PatchPathValidator.canonicalRelativePath(path) }
        }
        project.rules.append(rule)
        expectFailure { try PatchPackageCodec.validate(project) }
        print("Codec round-trip, password retention, tamper rejection and unsafe-path tests passed.")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
    static func expectFailure(_ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection") } catch { }
    }
}
