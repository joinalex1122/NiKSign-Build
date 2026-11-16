import Foundation
import MachOKit
import ArArchiveKit
import SWCompression

enum NiKDylibInjector {
    private static let lcLoadDylib: UInt32 = 0x0000000c
    private static let lcLoadWeakDylib: UInt32 = 0x80000018
    private static let mhMagic64: UInt32 = 0xfeedfacf
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf

    /// Extracts `.dylib` files from `.deb` or copies standalone `.dylib` files into `Payload/*.app/Frameworks`
    /// and injects `LC_LOAD_DYLIB` commands into the main application executable.
    static func inject(files: [URL], intoAppBundle appBundleURL: URL, executableName: String, weakLink: Bool = false) throws -> [String] {
        guard !files.isEmpty else { return [] }
        let fm = FileManager.default
        let frameworksDir = appBundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        try fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
        let executableURL = appBundleURL.appendingPathComponent(executableName)

        var injectedNames: [String] = []

        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "dylib" {
                let dylibName = try sanitizeFilename(fileURL.lastPathComponent)
                try NiKBinaryInspector.requireUnencrypted(at: fileURL)
                let destURL = frameworksDir.appendingPathComponent(dylibName)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: fileURL, to: destURL)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
                let installPath = "@executable_path/Frameworks/\(dylibName)"
                try injectLoadCommand(intoExecutable: executableURL, installName: installPath, weak: weakLink)
                injectedNames.append(dylibName)
            } else if ext == "deb" {
                let extracted = try extractDylibsFromDeb(at: fileURL, destinationDirectory: frameworksDir)
                guard !extracted.isEmpty else {
                    throw NiKError("Gói .deb (\(fileURL.lastPathComponent)) không chứa tệp .dylib nào.")
                }
                for dylibURL in extracted {
                    try NiKBinaryInspector.requireUnencrypted(at: dylibURL)
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dylibURL.path)
                    let dylibName = dylibURL.lastPathComponent
                    let installPath = "@executable_path/Frameworks/\(dylibName)"
                    try injectLoadCommand(intoExecutable: executableURL, installName: installPath, weak: weakLink)
                    injectedNames.append(dylibName)
                }
            } else {
                throw NiKError("Chỉ hỗ trợ chèn tệp .dylib hoặc .deb (nhận được .\(ext)).")
            }
        }
        return injectedNames
    }

    private static func sanitizeFilename(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".",
              trimmed != ".." else {
            throw NiKError("Tên tệp dylib không hợp lệ: \(raw)")
        }
        return trimmed
    }

    private static func extractDylibsFromDeb(at debURL: URL, destinationDirectory: URL) throws -> [URL] {
        let size = try debURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 67_108_864 else {
            throw NiKError("Gói .deb vượt giới hạn 64 MB.")
        }
        let data = try Data(contentsOf: debURL)
        let expectedCount = try NiKArchiveInspector.validateShortAR(data)
        let reader = try ArArchiveReader(archive: Array(data))
        guard reader.count == expectedCount else {
            throw NiKError("ArArchiveKit không đọc đủ mục trong gói .deb.")
        }

        var dataTarBytes: Data?
        var dataMemberName = ""
        for (header, content) in reader {
            let cleanName = header.name.hasSuffix("/") ? String(header.name.dropLast()) : header.name
            if cleanName.hasPrefix("data.tar") {
                dataTarBytes = Data(content)
                dataMemberName = cleanName
                break
            }
        }
        guard let rawPayload = dataTarBytes else {
            throw NiKError("Gói .deb thiếu thành phần data.tar.")
        }

        let tarData: Data
        if dataMemberName.hasSuffix(".gz") {
            tarData = try GzipArchive.unarchive(archive: rawPayload)
        } else if dataMemberName.hasSuffix(".xz") {
            tarData = try XZArchive.unarchive(archive: rawPayload)
        } else if dataMemberName.hasSuffix(".lzma") {
            tarData = try LZMA.decompress(data: rawPayload)
        } else if dataMemberName.hasSuffix(".tar") {
            tarData = rawPayload
        } else {
            throw NiKError("Định dạng nén \(dataMemberName) trong .deb chưa được hỗ trợ (hỗ trợ .tar, .gz, .xz, .lzma).")
        }

        let entries = try TarContainer.open(container: tarData)
        var extractedURLs: [URL] = []
        for entry in entries {
            guard entry.info.type == .regular,
                  entry.info.name.lowercased().hasSuffix(".dylib"),
                  let content = entry.data,
                  !content.isEmpty else {
                continue
            }
            let baseName = URL(fileURLWithPath: entry.info.name).lastPathComponent
            let safeName = try sanitizeFilename(baseName)
            let targetURL = destinationDirectory.appendingPathComponent(safeName)
            try content.write(to: targetURL, options: .atomic)
            extractedURLs.append(targetURL)
        }
        return extractedURLs
    }

    /// Injects an `LC_LOAD_DYLIB` or `LC_LOAD_WEAK_DYLIB` command into all 64-bit slices of a Mach-O executable.
    static func injectLoadCommand(intoExecutable executableURL: URL, installName: String, weak: Bool = false) throws {
        var binary = try Data(contentsOf: executableURL)
        guard binary.count >= 32 else {
            throw NiKError("Binary quá nhỏ để chứa Mach-O header.")
        }
        let magicBE = binary.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        let magicLE = binary.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }

        if magicLE == mhMagic64 {
            try patchThin64Slice(&binary, sliceOffset: 0, sliceLength: binary.count, installName: installName, weak: weak)
        } else if magicBE == fatMagic {
            let nfatArch = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).bigEndian })
            guard nfatArch > 0, nfatArch <= 16, binary.count >= 8 + nfatArch * 20 else {
                throw NiKError("Fat Mach-O header không hợp lệ.")
            }
            for i in 0..<nfatArch {
                let archOffset = 8 + i * 20
                let sliceOffset = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: archOffset + 8, as: UInt32.self).bigEndian })
                let sliceSize = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: archOffset + 12, as: UInt32.self).bigEndian })
                guard sliceOffset >= 0, sliceSize >= 32, sliceOffset + sliceSize <= binary.count else {
                    throw NiKError("Fat Mach-O slice vượt phạm vi tệp.")
                }
                let sliceMagic = binary.withUnsafeBytes { $0.load(fromByteOffset: sliceOffset, as: UInt32.self).littleEndian }
                if sliceMagic == mhMagic64 {
                    try patchThin64Slice(&binary, sliceOffset: sliceOffset, sliceLength: sliceSize, installName: installName, weak: weak)
                }
            }
        } else if magicBE == fatMagic64 {
            let nfatArch = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).bigEndian })
            guard nfatArch > 0, nfatArch <= 16, binary.count >= 8 + nfatArch * 32 else {
                throw NiKError("Fat64 Mach-O header không hợp lệ.")
            }
            for i in 0..<nfatArch {
                let archOffset = 8 + i * 32
                let sliceOffset = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: archOffset + 8, as: UInt64.self).bigEndian })
                let sliceSize = Int(binary.withUnsafeBytes { $0.load(fromByteOffset: archOffset + 16, as: UInt64.self).bigEndian })
                guard sliceOffset >= 0, sliceSize >= 32, sliceOffset + sliceSize <= binary.count else {
                    throw NiKError("Fat64 Mach-O slice vượt phạm vi tệp.")
                }
                let sliceMagic = binary.withUnsafeBytes { $0.load(fromByteOffset: sliceOffset, as: UInt32.self).littleEndian }
                if sliceMagic == mhMagic64 {
                    try patchThin64Slice(&binary, sliceOffset: sliceOffset, sliceLength: sliceSize, installName: installName, weak: weak)
                }
            }
        } else {
            throw NiKError("Chỉ hỗ trợ chèn dylib vào binary Mach-O 64-bit.")
        }

        try binary.write(to: executableURL, options: .atomic)
    }

    private static func patchThin64Slice(
        _ data: inout Data,
        sliceOffset: Int,
        sliceLength: Int,
        installName: String,
        weak: Bool
    ) throws {
        let headerSize = 32 // sizeof(mach_header_64)
        let ncmds = Int(readUInt32LE(data, at: sliceOffset + 16))
        let sizeofcmds = Int(readUInt32LE(data, at: sliceOffset + 20))
        guard ncmds >= 0, sizeofcmds >= 0, headerSize + sizeofcmds <= sliceLength else {
            throw NiKError("Mach-O load commands vượt biên slice.")
        }

        // Scan existing load commands to avoid duplicate injection and find minimum section file offset.
        var cursor = sliceOffset + headerSize
        let commandsEnd = cursor + sizeofcmds
        var minSectionOffset = sliceLength

        for _ in 0..<ncmds {
            guard cursor + 8 <= commandsEnd else {
                throw NiKError("Load command bị cắt ngắn trong Mach-O.")
            }
            let cmd = readUInt32LE(data, at: cursor)
            let cmdsize = Int(readUInt32LE(data, at: cursor + 4))
            guard cmdsize >= 8, cursor + cmdsize <= commandsEnd else {
                throw NiKError("Kích thước load command không hợp lệ.")
            }
            if cmd == lcLoadDylib || cmd == lcLoadWeakDylib {
                if cmdsize >= 24 {
                    let nameOffset = Int(readUInt32LE(data, at: cursor + 8))
                    if nameOffset >= 24 && nameOffset < cmdsize {
                        let strBytes = data.subdata(in: (cursor + nameOffset)..<(cursor + cmdsize))
                        let existing = String(decoding: strBytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                        if existing == installName {
                            return // Already present
                        }
                    }
                }
            } else if cmd == 0x19 { // LC_SEGMENT_64
                if cmdsize >= 72 {
                    let nsects = Int(readUInt32LE(data, at: cursor + 64))
                    var sectCursor = cursor + 72
                    for _ in 0..<nsects {
                        if sectCursor + 80 <= cursor + cmdsize {
                            let sectOffset = Int(readUInt32LE(data, at: sectCursor + 48))
                            if sectOffset > 0 && sectOffset < minSectionOffset {
                                minSectionOffset = sectOffset
                            }
                        }
                        sectCursor += 80
                    }
                }
            }
            cursor += cmdsize
        }

        let nameBytes = Array(installName.utf8) + [0]
        let rawSize = 24 + nameBytes.count
        let alignedSize = (rawSize + 7) & ~7
        let newEndRelative = headerSize + sizeofcmds + alignedSize
        guard newEndRelative <= minSectionOffset else {
            throw NiKError("Mach-O header không còn đủ khoảng trống padding để chèn thêm LC_LOAD_DYLIB (\(installName)).")
        }

        var cmdBuffer = Data(count: alignedSize)
        writeUInt32LE(&cmdBuffer, at: 0, value: weak ? lcLoadWeakDylib : lcLoadDylib)
        writeUInt32LE(&cmdBuffer, at: 4, value: UInt32(alignedSize))
        writeUInt32LE(&cmdBuffer, at: 8, value: 24) // offset of name string in dylib_command
        writeUInt32LE(&cmdBuffer, at: 12, value: 2) // timestamp
        writeUInt32LE(&cmdBuffer, at: 16, value: 0x00010000) // current_version 1.0.0
        writeUInt32LE(&cmdBuffer, at: 20, value: 0x00010000) // compatibility_version 1.0.0
        cmdBuffer.replaceSubrange(24..<(24 + nameBytes.count), with: nameBytes)

        let insertRange = commandsEnd..<(commandsEnd + alignedSize)
        data.replaceSubrange(insertRange, with: cmdBuffer)
        writeUInt32LE(&data, at: sliceOffset + 16, value: UInt32(ncmds + 1))
        writeUInt32LE(&data, at: sliceOffset + 20, value: UInt32(sizeofcmds + alignedSize))
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func writeUInt32LE(_ data: inout Data, at offset: Int, value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { src in
            data.replaceSubrange(offset..<(offset + 4), with: src)
        }
    }
}
