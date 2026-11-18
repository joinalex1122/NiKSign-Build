import Foundation
import Combine

@MainActor final class NiKFileBrowserController: ObservableObject {
    let root: URL
    @Published private(set) var state = NiKFileBrowserState()
    @Published var message: String?
    private var store: NiKFileBrowserStateStore?
    private struct Position: Hashable { let tabID: UUID; let location: NiKFileLocation }
    private var anchors: [Position: String] = [:]
    var selected: NiKFileBrowserTab { state.selected }
    var directory: URL { selected.location.components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) } }
    var scrollAnchor: String? {
        get { anchors[Position(tabID: state.selectedID, location: selected.location)] }
        set { anchors[Position(tabID: state.selectedID, location: selected.location)] = newValue }
    }
    init(root: URL) {
        self.root = root.standardizedFileURL
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NiKSign/FileBrowser")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let name = root.lastPathComponent == "IPALibrary" ? "ipa.json" : "documents.json"
            let store = try NiKFileBrowserStateStore(url: support.appendingPathComponent(name))
            self.store = store; state = store.state
        } catch { message = error.localizedDescription }
    }
    private func change(_ action: (inout NiKFileBrowserState) throws -> Void) {
        do {
            guard let store else { throw NiKFileBrowserState.Failure(message: "Không nạp được index phiên; chưa ghi đè cấu hình cũ.") }
            var updated = state
            try action(&updated)
            try store.commit(updated)
            state = updated
        } catch { message = error.localizedDescription }
    }
    func open(_ url: URL) {
        do { let location = try NiKFileLocation.from(url, root: root); change { try $0.navigate(location) } }
        catch { message = error.localizedDescription }
    }
    func openFavorite(_ location: NiKFileLocation) {
        do { let url = try location.resolve(in: root); open(url) } catch { message = error.localizedDescription }
    }
    func newTab() { change { try $0.addTab() } }
    func closeTab(_ id: UUID) {
        guard state.tabs.count > 1 else { return }
        change { $0.closeTab(id) }
        if !state.tabs.contains(where: { $0.id == id }) { anchors = anchors.filter { $0.key.tabID != id } }
    }
    func rememberAnchor(_ anchor: String?, tabID: UUID) {
        guard let tab = state.tabs.first(where: { $0.id == tabID }) else { return }
        anchors[Position(tabID: tabID, location: tab.location)] = anchor
    }
    func select(_ id: UUID) { change { if $0.tabs.contains(where: { $0.id == id }) { $0.selectedID = id } } }
    func travel(_ offset: Int) {
        change { state in
            guard let index = state.tabs.firstIndex(where: { $0.id == state.selectedID }) else { return }
            let next = state.tabs[index].historyIndex + offset
            guard state.tabs[index].history.indices.contains(next) else { return }
            _ = try state.tabs[index].history[next].resolve(in: root)
            state.tabs[index].historyIndex = next
            state.tabs[index].query = ""
        }
    }
    func setOptions(query: String, sort: NiKFileBrowserSort) {
        guard selected.query != query || selected.sort != sort else { return }
        change { state in
            guard let index = state.tabs.firstIndex(where: { $0.id == state.selectedID }) else { return }
            state.tabs[index].query = query; state.tabs[index].sort = sort
        }
    }
    func toggleHidden() { change { state in if let index = state.tabs.firstIndex(where: { $0.id == state.selectedID }) { state.tabs[index].showsHidden.toggle() } } }
    func toggleFavorite() {
        change { state in
            let location = state.selected.location
            if let index = state.favorites.firstIndex(of: location) { state.favorites.remove(at: index) }
            else { state.favorites.append(location) }
        }
    }
}
