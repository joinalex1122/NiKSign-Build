import Foundation
import ZIPFoundation

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func expectFailure(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    fatalError("Expected failure")
}
func zip(_ name: String, _ entries: [(String, String)]) throws -> URL {
    let url = root.appendingPathComponent(name + ".zip")
    let archive = try Archive(url: url, accessMode: .create)
    for (path, text) in entries {
        let data = Data(text.utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
        }
    }
    return url
}
let valid = try zip("valid", [("nested/Mẫu.txt", "hello")])
let target = root.appendingPathComponent("out")
try NiKArchive.extract(valid, to: target)
let actual = try String(contentsOf: target.appendingPathComponent("nested/Mẫu.txt"))
precondition(actual == "hello")
try expectFailure { try NiKArchive.extract(valid, to: target) }
try expectFailure { try NiKArchive.extract(valid, to: root.appendingPathComponent("limit"), limit: 4) }
try expectFailure { try NiKArchive.extract(valid, to: root.appendingPathComponent("count"), entryLimit: 0) }
for (name, entries) in [
    ("traversal", [("../escape", "x")]),
    ("absolute", [("/escape", "x")]),
    ("duplicate", [("Name", "x"), ("name", "y")]),
    ("collision", [("file", "x"), ("file/child", "y")])
] {
    let source = try zip(name, entries)
    let dest = root.appendingPathComponent(name)
    try expectFailure { try NiKArchive.extract(source, to: dest) }
    precondition(!fm.fileExists(atPath: dest.path))
}
for name in ["", ".", "..", "../outside", "a/b", "a\\b", "a\0b"] {
    try expectFailure { _ = try NiKFileOperations.child(named: name, in: root) }
}
try expectFailure { try NiKFileOperations.transfer(target, into: target, copy: true) }
try expectFailure { try NiKFileOperations.transfer(target, into: target.appendingPathComponent("nested"), copy: false) }
let copies = root.appendingPathComponent("copies")
try fm.createDirectory(at: copies, withIntermediateDirectories: false)
try NiKFileOperations.transfer(target, into: copies, copy: true)
try expectFailure { try NiKFileOperations.transfer(target, into: copies, copy: false) }
precondition(fm.fileExists(atPath: target.path))
let certZip = try zip("cert", [("cert.p12", "key"), ("cert.mobileprovision", "profile"), ("password.txt", " pass \n")])
let cert = try NiKCertZipHelper.extractPairAndPassword(from: certZip)
defer { try? fm.removeItem(at: cert.tempDir) }
precondition(cert.password == " pass ")
let ambiguous = try zip("ambiguous", [("a.p12", "a"), ("b.p12", "b"), ("cert.mobileprovision", "p")])
try expectFailure { _ = try NiKCertZipHelper.extractPairAndPassword(from: ambiguous) }
let readme = try zip("readme", [("cert.p12", "k"), ("cert.mobileprovision", "p"), ("README.txt", "Read this")])
let noPassword = try NiKCertZipHelper.extractPairAndPassword(from: readme)
defer { try? fm.removeItem(at: noPassword.tempDir) }
precondition(noPassword.password == nil)
let stages = try fm.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".unzip-") || $0.hasPrefix(".copy-") }
precondition(stages.isEmpty)
print("PASS: extraction, Unicode, no overwrite, limits, traversal, duplicate/collision cleanup, file names, self-transfer, certificate ambiguity and password whitespace")
let linkZip = root.appendingPathComponent("symlink.zip")
do {
    let archive = try Archive(url: linkZip, accessMode: .create)
    let bytes = Data("../outside".utf8)
    try archive.addEntry(with: "link", type: .symlink, uncompressedSize: Int64(bytes.count)) { _, _ in bytes }
}
try expectFailure { try NiKArchive.extract(linkZip, to: root.appendingPathComponent("symlink-out")) }
let corrupt = root.appendingPathComponent("crc.zip")
do {
    let archive = try Archive(url: corrupt, accessMode: .create)
    let bytes = Data("UNIQUE_PAYLOAD_CRC".utf8)
    try archive.addEntry(with: "test", type: .file, uncompressedSize: Int64(bytes.count)) { _, _ in bytes }
}
var corruptBytes = try Data(contentsOf: corrupt)
let payloadRange = corruptBytes.range(of: Data("UNIQUE_PAYLOAD_CRC".utf8))!
corruptBytes[payloadRange.lowerBound] ^= 0x01
try corruptBytes.write(to: corrupt)
try expectFailure { try NiKArchive.extract(corrupt, to: root.appendingPathComponent("crc-out")) }
precondition(!fm.fileExists(atPath: root.appendingPathComponent("crc-out").path))
print("PASS: symlink rejection and corrupted CRC cleanup")

func signedFixture(_ name: String, bundleID: String, signature: Bool, executable: Data) throws -> URL {
    let url = root.appendingPathComponent(name + ".ipa")
    let archive = try Archive(url: url, accessMode: .create)
    let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Demo"], format: .xml, options: 0)
    var files = ["Payload/Demo.app/Info.plist": info, "Payload/Demo.app/Demo": executable, "Payload/Demo.app/embedded.mobileprovision": Data("fixture".utf8)]
    if signature { files["Payload/Demo.app/_CodeSignature/CodeResources"] = Data("fixture".utf8) }
    for path in files.keys.sorted() {
        let data = files[path]!
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in
            data.subdata(in: Int(offset)..<min(Int(offset) + size, data.count))
        }
    }
    return url
}
let structuralFixture = try signedFixture("structural", bundleID: "com.example.demo", signature: true, executable: Data([0xcf, 0xfa, 0xed, 0xfe] + [UInt8](repeating: 0, count: 28)))
try NiKSignedOutputValidator.validate(structuralFixture, expectedBundleID: "com.example.demo")
try expectFailure { try NiKSignedOutputValidator.validate(structuralFixture, expectedBundleID: "com.other.app") }
let missingSignature = try signedFixture("missing-signature", bundleID: "com.example.demo", signature: false, executable: Data([0xcf, 0xfa, 0xed, 0xfe] + [UInt8](repeating: 0, count: 28)))
try expectFailure { try NiKSignedOutputValidator.validate(missingSignature, expectedBundleID: "com.example.demo") }
let invalidBinary = try signedFixture("bad-executable", bundleID: "com.example.demo", signature: true, executable: Data("not a binary".utf8))
try expectFailure { try NiKSignedOutputValidator.validate(invalidBinary, expectedBundleID: "com.example.demo") }
print("PASS: output structure/CRC, exact bundle ID, signing resource presence and Mach-O marker; fixture does not assert cryptographic signature validity")
