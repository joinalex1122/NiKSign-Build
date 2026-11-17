import Foundation

enum NiKCertZipHelper {
    static func extractPairAndPassword(from zipURL: URL) throws -> (p12: URL, provision: URL, password: String?, tempDir: URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nikcert-\(UUID().uuidString)")
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: tmpDir) } }
        try NiKArchive.extract(zipURL, to: tmpDir, limit: 16 * 1_048_576, entryLimit: 256)

        var p12URL: URL?
        var provURL: URL?
        var txtURLs: [URL] = []

        if let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator {
                let path = file.path
                if path.contains("__MACOSX") || file.lastPathComponent.hasPrefix("._") { continue }
                let ext = file.pathExtension.lowercased()
                guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
                if ext == "p12" {
                    guard p12URL == nil else { throw NiKArchive.Failure(message: "ZIP chứa nhiều .p12; hãy chọn riêng từng cặp chứng chỉ.") }
                    p12URL = file
                } else if ext == "mobileprovision" {
                    guard provURL == nil else { throw NiKArchive.Failure(message: "ZIP chứa nhiều .mobileprovision; hãy chọn riêng từng cặp chứng chỉ.") }
                    provURL = file
                } else if ext == "txt" {
                    txtURLs.append(file)
                }
            }
        }

        guard let foundP12 = p12URL else {
            throw NSError(domain: "NiKCert", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp .p12 trong gói .zip"])
        }
        guard let foundProv = provURL else {
            throw NSError(domain: "NiKCert", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp .mobileprovision trong gói .zip"])
        }

        var foundPass: String?
        // Only use an unambiguous password file; never treat a README as a password.
        let passwordFiles = txtURLs.filter {
            ["pass", "password", "pwd", "matkhau", "mật khẩu"].contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        if passwordFiles.count == 1, let txt = passwordFiles.first,
           (try txt.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 16_384 {
            foundPass = try String(contentsOf: txt, encoding: .utf8).trimmingCharacters(in: .newlines)
        }
        keep = true
        return (foundP12, foundProv, foundPass, tmpDir)
    }

    static func findPairInDirectory(for fileURL: URL) -> (p12: URL?, provision: URL?) {
        let folder = fileURL.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let ext = fileURL.pathExtension.lowercased()
        let base = fileURL.deletingPathExtension().lastPathComponent.lowercased()

        let p12Candidates = items.filter { $0.pathExtension.lowercased() == "p12" && !$0.lastPathComponent.hasPrefix("._") }
        let provCandidates = items.filter { $0.pathExtension.lowercased() == "mobileprovision" && !$0.lastPathComponent.hasPrefix("._") }

        if ext == "p12" {
            let matchedProv = provCandidates.first { $0.deletingPathExtension().lastPathComponent.lowercased() == base } ?? (provCandidates.count == 1 ? provCandidates.first : nil)
            return (fileURL, matchedProv)
        } else if ext == "mobileprovision" {
            let matchedP12 = p12Candidates.first { $0.deletingPathExtension().lastPathComponent.lowercased() == base } ?? (p12Candidates.count == 1 ? p12Candidates.first : nil)
            return (matchedP12, fileURL)
        }
        return (nil, nil)
    }

    static func documentsCertificateFiles() -> [URL] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var results: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator {
                let path = file.path
                if path.contains("__MACOSX") || file.lastPathComponent.hasPrefix("._") { continue }
                let ext = file.pathExtension.lowercased()
                if ext == "p12" || ext == "mobileprovision" || ext == "zip" {
                    results.append(file)
                }
            }
        }
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

