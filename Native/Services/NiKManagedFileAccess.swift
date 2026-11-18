import Foundation

@MainActor enum NiKManagedFileAccess {
    static func reserve(_ paths: [URL], allowManagedLibrary: Bool = false) throws -> NiKFileMutationReservations.Lease {
        let protected = NiKSigningQueue.shared.jobs.filter { !$0.state.isTerminal }.flatMap { [$0.input] + $0.options.injectedFiles }
        return try NiKFileMutationReservations.shared.reserve(paths, protected: protected, readOnlyRoots: allowManagedLibrary ? [] : [NiKLibrary.root])
    }
    static func validateCreationDirectory(_ directory: URL) throws {
        guard !NiKFileMutationReservations.shared.isReserved(directory) else {
            throw NiKError("Thư mục đang có thao tác khác; hãy đợi hoàn tất trước khi nhập.")
        }
        guard !NiKFileMutationReservations.isWithin(directory, root: NiKLibrary.root) else {
            throw NiKError("Hãy nhập IPA bằng màn Thư viện để cập nhật danh mục an toàn.")
        }
    }
}
