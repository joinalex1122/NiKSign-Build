import Foundation

enum NiKFileBrowserSort: String, Codable, Sendable { case name, date, size }
struct NiKFileLocation: Codable, Hashable, Sendable {
    var components: [String] = []
    var name: String { components.last ?? "Documents" }
    func validate() throws {
        guard components.count <= 64, components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 && !$0.contains("/") && !$0.contains("\\") &&
            !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }) else { throw NiKFileBrowserState.Failure(message: "Vị trí tab không an toàn hoặc quá sâu.") }
    }
    func resolve(in root: URL) throws -> URL {
        guard root.isFileURL else { throw NiKFileBrowserState.Failure(message: "Root phải là thư mục cục bộ.") }
        try validate()
        var current = root.standardizedFileURL
        func check(_ url: URL) throws {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw NiKFileBrowserState.Failure(message: "Vị trí không còn là thư mục hoặc là symlink.")
            }
        }
        try check(current)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            try check(current)
        }
        return current
    }
    static func from(_ url: URL, root: URL) throws -> Self {
        guard root.isFileURL, url.isFileURL else { throw NiKFileBrowserState.Failure(message: "Vị trí phải là thư mục cục bộ.") }
        let parent = root.standardizedFileURL.path, target = url.standardizedFileURL.path
        guard target == parent || target.hasPrefix(parent + "/") else { throw NiKFileBrowserState.Failure(message: "Vị trí nằm ngoài thư mục được quản lý.") }
        let location = Self(components: target == parent ? [] : String(target.dropFirst(parent.count + 1)).split(separator: "/").map(String.init))
        _ = try location.resolve(in: root)
        return location
    }
}
struct NiKFileBrowserTab: Codable, Identifiable, Sendable {
    let id: UUID
    var history: [NiKFileLocation]
    var historyIndex: Int
    var query: String = ""
    var sort: NiKFileBrowserSort = .name
    var showsHidden = false
    var location: NiKFileLocation { history[historyIndex] }
    init(location: NiKFileLocation = .init()) {
        id = UUID(); history = [location]; historyIndex = 0
    }
}
struct NiKFileBrowserState: Codable, Sendable {
    let version: Int
    var tabs: [NiKFileBrowserTab]
    var selectedID: UUID
    var favorites: [NiKFileLocation] = []
    var selected: NiKFileBrowserTab { tabs.first { $0.id == selectedID }! }
    init() {
        let tab = NiKFileBrowserTab()
        version = 1; tabs = [tab]; selectedID = tab.id
    }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    func validate() throws {
        guard version == 1, (1...12).contains(tabs.count), Set(tabs.map(\.id)).count == tabs.count,
              tabs.contains(where: { $0.id == selectedID }), favorites.count <= 1_000, Set(favorites).count == favorites.count else {
            throw Failure(message: "Phiên tệp có version/ID/tab/yêu thích không hợp lệ.")
        }
        for tab in tabs {
            guard (1...100).contains(tab.history.count), tab.history.indices.contains(tab.historyIndex), tab.query.utf8.count <= 2_048 else {
                throw Failure(message: "Lịch sử hoặc tìm kiếm tab vượt giới hạn.")
            }
            for location in tab.history { try location.validate() }
        }
        for location in favorites { try location.validate() }
    }
    mutating func navigate(_ location: NiKFileLocation) throws {
        try location.validate()
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }) else { throw Failure(message: "Không tìm thấy tab.") }
        if tabs[index].location == location { return }
        tabs[index].history = Array(tabs[index].history.prefix(tabs[index].historyIndex + 1)) + [location]
        if tabs[index].history.count > 100 { tabs[index].history.removeFirst() }
        tabs[index].historyIndex = tabs[index].history.count - 1
        tabs[index].query = ""
    }
    mutating func addTab() throws {
        guard tabs.count < 12 else { throw Failure(message: "Tối đa 12 tab.") }
        let tab = NiKFileBrowserTab(location: selected.location)
        tabs.append(tab); selectedID = tab.id
    }
    mutating func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }
}

final class NiKFileBrowserStateStore {
    let url: URL
    private(set) var state: NiKFileBrowserState
    private var baseline: Data?
    init(url: URL) throws {
        self.url = url
        if let data = try Self.read(url) {
            state = try JSONDecoder().decode(NiKFileBrowserState.self, from: data)
            try state.validate()
            baseline = data
        } else { state = .init() }
    }
    private static func read(_ url: URL) throws -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_048_576 else {
            throw NiKFileBrowserState.Failure(message: "Index phiên tệp không hợp lệ hoặc vượt 1 MB.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw NiKFileBrowserState.Failure(message: "Index phiên tệp vượt 1 MB.") }
        return data
    }
    func commit(_ updated: NiKFileBrowserState) throws {
        try updated.validate()
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 1_048_576 else { throw NiKFileBrowserState.Failure(message: "Index phiên tệp vượt 1 MB.") }
        guard try Self.read(url) == baseline else { throw NiKFileBrowserState.Failure(message: "Index phiên tệp đã đổi bên ngoài; chưa ghi đè. Hãy mở lại màn Tệp.") }
        try data.write(to: url, options: .atomic)
        baseline = data; state = updated
    }
}
