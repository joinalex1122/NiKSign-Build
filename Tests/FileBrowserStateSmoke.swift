import Foundation

@main struct FileBrowserStateSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected file-browser state failure")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("Tài liệu/Con"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let location = try NiKFileLocation.from(root.appendingPathComponent("Tài liệu/Con"), root: root)
        precondition(location.components == ["Tài liệu", "Con"])
        fails { _ = try NiKFileLocation.from(root.deletingLastPathComponent(), root: root) }
        fails { _ = try NiKFileLocation(components: [".."]).resolve(in: root) }
        fails { _ = try NiKFileLocation(components: ["a/b"]).resolve(in: root) }
        fails { _ = try NiKFileLocation(components: ["missing"]).resolve(in: root) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("Tài liệu"))
        fails { _ = try NiKFileLocation(components: ["alias"]).resolve(in: root) }
        let url = root.appendingPathComponent("browser.json")
        let store = try NiKFileBrowserStateStore(url: url)
        var state = store.state
        let firstID = state.selectedID
        try state.navigate(location)
        state.tabs[0].query = "tìm kiếm"; state.tabs[0].sort = .size; state.tabs[0].showsHidden = true
        state.favorites = [location]
        try state.addTab()
        let secondID = state.selectedID
        try state.navigate(.init())
        precondition(state.tabs.count == 2 && state.tabs[0].query == "tìm kiếm" && state.selected.location.components.isEmpty)
        state.selectedID = firstID
        precondition(state.selected.location == location && state.selected.sort == .size && state.selected.showsHidden)
        try store.commit(state)
        let reopened = try NiKFileBrowserStateStore(url: url)
        precondition(reopened.state.selectedID == firstID && reopened.state.favorites == [location])
        let encoded = try Data(contentsOf: url)
        precondition(!String(decoding: encoded, as: UTF8.self).contains(root.path))
        var invalid = state; invalid.selectedID = UUID()
        fails { try store.commit(invalid) }
        invalid = state; invalid.tabs[0].historyIndex = 999
        fails { try store.commit(invalid) }
        invalid = state; invalid.favorites.append(location)
        fails { try store.commit(invalid) }
        for index in 0..<110 { try state.navigate(.init(components: ["folder\(index)"])) }
        precondition(state.selected.history.count == 100 && state.selected.historyIndex == 99)
        while state.tabs.count < 12 { try state.addTab() }
        fails { try state.addTab() }
        for id in state.tabs.map(\.id) { state.closeTab(id) }
        precondition(state.tabs.count == 1)
        try state.validate()
        precondition(firstID != secondID)
        let corruption = Data("broken settings".utf8)
        try corruption.write(to: url, options: .atomic)
        fails { try store.commit(state) }
        fails { _ = try NiKFileBrowserStateStore(url: url) }
        let preserved = try Data(contentsOf: url)
        precondition(preserved == corruption)
        print("PASS: independent tabs/query/sort/hidden/history, relative persistence/favorites, tab/history bounds, invalid state/path/symlink rejection and corrupt/stale settings preservation")
    }
}
