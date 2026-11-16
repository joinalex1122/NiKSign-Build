import SwiftUI

struct NiKComponent: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let repository: URL
    let ref: String
    let revision: String
    let license: String
    let status: String
    let note: String
    let licenseFile: String
}

struct NiKLicensesView: View {
    @State private var components: [NiKComponent] = []
    @State private var loadError: String?
    var body: some View {
        List {
            if let loadError { Text(loadError).foregroundStyle(.red) }
            ForEach(components) { item in
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(item.note)
                            Text(item.status == "reference" ? "Nguồn tham khảo — chưa tích hợp chức năng" : "Đã nối vào mã build — chưa xác minh trên iPhone")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("Repository", destination: item.repository)
                            Text("\(item.ref)\n\(item.revision)").font(.caption.monospaced()).textSelection(.enabled)
                            Text(licenseText(item)).font(.caption.monospaced()).textSelection(.enabled)
                        }.padding()
                    }.navigationTitle(item.name)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(item.name); Spacer(); Text(item.license).font(.caption).foregroundStyle(.cyan) }
                        Text(item.status == "reference" ? "Tham khảo" : "Đã nối mã build").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Giấy phép mã nguồn mở")
        .task {
            do {
                guard let url = Bundle.main.url(forResource: "components", withExtension: "json") else { throw NiKError("Thiếu danh mục thư viện trong bundle.") }
                components = try JSONDecoder().decode([NiKComponent].self, from: Data(contentsOf: url))
            } catch { loadError = error.localizedDescription }
        }
    }
    private func licenseText(_ item: NiKComponent) -> String {
        guard let url = Bundle.main.url(forResource: item.licenseFile, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Không tìm thấy tệp giấy phép." }
        return text
    }
}
