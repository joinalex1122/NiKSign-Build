import SwiftUI

@main
struct NiKSignApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var certificates = NiKCertificateStore.shared
    @State private var toolImport: NiKToolImport?
    init() {
        if UserDefaults.standard.string(forKey: "nik.language") == nil {
            let old = UserDefaults.standard.string(forKey: "appLanguage")
            UserDefaults.standard.set(old == "en" ? "en" : "vi", forKey: "nik.language")
        }
        UserDefaults.standard.removeObject(forKey: "nik.mode")
    }
    var body: some Scene {
        WindowGroup {
            NiKPreviewRoot()
                .sheet(item: $toolImport) { NiKToolsSheet(initialURL: $0.url) }
                .task(id: scenePhase == .active ? certificates.selectedProfile?.id.uuidString ?? "none" : "inactive") {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await certificates.checkSelectedRevocationIfDue()
                        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                    }
                }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    let ext = url.pathExtension.lowercased()
                    if ext == "ipa" { Task { await NiKLibrary.shared.receive(url) } }
                    else if ["p12", "mobileprovision", "dylib", "deb"].contains(ext) {
                        toolImport = NiKToolImport(url: url)
                    }
                }
        }
    }
}
