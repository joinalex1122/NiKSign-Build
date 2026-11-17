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
let stages = try fm.contentsOfDirectory(atPath: root).filter { $0.hasPrefix(".unzip-") || $0.hasPrefix(".copy-") }
precondition(stages.isEmpty)
print("PASS: extraction, Unicode, no overwrite, limits, traversal, duplicate/collision cleanup, file names, self-transfer, certificate ambiguity and password whitespace")
