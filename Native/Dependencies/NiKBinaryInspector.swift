import Foundation
import MachOKit

struct NiKBinaryInspector {
    static func slices(at url: URL) throws -> [MachOFile] {
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let file): return [file]
        case .fat(let file): return try file.machOFiles()
        }
    }
    static func requireUnencrypted(at url: URL) throws {
        let images = try slices(at: url)
        guard !images.isEmpty, images.allSatisfy({ !$0.isEncrypted }) else {
            throw NiKError("Binary đang mã hóa hoặc không có Mach-O slice. Không thể ký lại để cài như IPA thông thường.")
        }
    }
    static func report(at url: URL) throws -> String {
        try slices(at: url).enumerated().map { index, file in
            "Slice \(index + 1): \(file.is64Bit ? "64-bit" : "32-bit")\nMã hóa: \(file.isEncrypted ? "Có" : "Không")\nLoad commands: \(file.header.ncmds)\nRPATH: \(file.rpaths.joined(separator: ", "))"
        }.joined(separator: "\n\n")
    }
}
