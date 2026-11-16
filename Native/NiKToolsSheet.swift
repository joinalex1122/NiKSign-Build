import SwiftUI

struct NiKToolImport: Identifiable {
    let id = UUID()
    let url: URL
}

struct NiKToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialURL: URL? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NiKSign").font(.headline)
                Spacer()
                Button("Đóng") { dismiss() }
            }.padding()
            NiKSignView(initialURL: initialURL)
        }
        .interactiveDismissDisabled()
    }
}
