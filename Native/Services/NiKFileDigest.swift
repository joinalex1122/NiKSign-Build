import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum NiKFileDigest {
    static func sha256(file: URL) throws -> String {
        #if canImport(CryptoKit)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
        #elseif os(Linux)
        return try linuxDigest(arguments: ["--zero", "--", file.path], input: nil)
        #else
        throw Failure.unavailable
        #endif
    }
    static func sha256(data: Data) throws -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #elseif os(Linux)
        return try linuxDigest(arguments: [], input: data)
        #else
        throw Failure.unavailable
        #endif
    }
    #if os(Linux)
    // Linux-only regression harness; the Apple application uses CryptoKit above.
    private static func linuxDigest(arguments: [String], input: Data?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        let pipe = input == nil ? nil : Pipe()
        if let pipe { process.standardInput = pipe }
        try process.run()
        if let input, let pipe {
            try pipe.fileHandleForWriting.write(contentsOf: input)
            try pipe.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)?.split(separator: " ").first,
              value.count == 64 else { throw Failure.unavailable }
        return String(value)
    }
    #endif
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Không tính được SHA-256 của dữ liệu." }
    }
}
