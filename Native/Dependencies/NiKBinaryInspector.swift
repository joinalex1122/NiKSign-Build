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
    static func requireSupportedSigningContainer(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let magic = try handle.read(upToCount: 4); try handle.close()
        if magic == Data([0xca,0xfe,0xba,0xbf]) || magic == Data([0xbf,0xba,0xfe,0xca]) { throw NiKError("Zsign hiện không hỗ trợ FAT64. Cần IPA arm64/FAT32 thay vì xuất bản chưa ký đủ.") }
    }
    static func requireApplicationExecutable(at url: URL) throws {
        try requireSupportedSigningContainer(at: url)
        let images = try slices(at: url)
        guard !images.isEmpty, images.allSatisfy({ $0.header.fileType == .execute }),
              images.contains(where: { $0.header.cpuType == .arm64 }) else { throw NiKError("Ứng dụng cần executable MH_EXECUTE có arm64 cho iPhone này.") }
        try requireUnencrypted(at: url)
    }
    static func requireFrameworkExecutable(at url: URL) throws {
        try requireSupportedSigningContainer(at: url)
        let images = try slices(at: url)
        guard !images.isEmpty, images.allSatisfy({ $0.header.fileType == .dylib }), images.contains(where: { $0.header.cpuType == .arm64 }) else { throw NiKError("Framework cần thư viện MH_DYLIB có arm64: " + url.lastPathComponent) }
        try requireUnencrypted(at: url)
    }
    static func isRuntimeCode(at url: URL) throws -> Bool {
        try slices(at: url).contains { image in
            guard let type = image.header.fileType else { return false }
            return type == .execute || type == .dylib || type == .dylinker || type == .bundle
        }
    }
    // Structural postcondition; native CMS cryptography is covered by zsign_cms_test.py.
    static func requireSignedIdentity(at url: URL, applicationID: String, teamID: String, allowedEntitlements: [String: Any]) throws {
        let images = try slices(at: url)
        guard !images.isEmpty else { throw NiKError("Bundle không có Mach-O slice.") }
        for image in images {
            guard let signature = image.codeSign, let cms = signature.signatureData, !cms.isEmpty,
                  let entitlements = signature.embeddedEntitlements,
                  entitlements["application-identifier"] as? String == applicationID,
                  entitlements["com.apple.developer.team-identifier"] as? String == teamID else {
                throw NiKError("Chữ ký thiếu CMS hoặc sai định danh trong " + url.lastPathComponent)
            }
            try NiKProvisioningValidation.validateEntitlements(entitlements, allowed: allowedEntitlements, applicationID: applicationID, teamID: teamID)
        }
    }
    static func requireSignedCode(at url: URL, certificateDER: Data, teamID: String) throws {
        let images = try slices(at: url)
        guard !images.isEmpty else { throw NiKError("Không có Mach-O slice: " + url.lastPathComponent) }
        for image in images {
            guard !image.isEncrypted, let signature = image.codeSign,
                  signature.codeDirectory != nil, let cms = signature.signatureData, !cms.isEmpty else {
                throw NiKError("Mã lồng nhau thiếu CodeDirectory/CMS hoặc còn mã hóa: " + url.lastPathComponent)
            }
            guard let container = signature.superBlob,
                  let index = signature.blobIndices(of: container).first(where: { $0.type == .codedirectory }),
                  let directory = signature.blobData(in: container, at: index, includesGenericInfo: true),
                  signature.codeDirectories.allSatisfy({ $0.teamId(in: signature) == teamID }) else { throw NiKError("CodeDirectory thiếu hoặc sai Team ID: " + url.lastPathComponent) }
            try NiKProvisioningValidation.verifyDetachedCMS(cms, content: directory, certificateDER: certificateDER)
        }
    }
    static func report(at url: URL) throws -> String {
        try slices(at: url).enumerated().map { index, file in
            "Slice \(index + 1): \(file.is64Bit ? "64-bit" : "32-bit")\nMã hóa: \(file.isEncrypted ? "Có" : "Không")\nLoad commands: \(file.header.ncmds)\nRPATH: \(file.rpaths.joined(separator: ", "))"
        }.joined(separator: "\n\n")
    }
}
