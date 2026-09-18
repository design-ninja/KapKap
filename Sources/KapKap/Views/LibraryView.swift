import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var store: CaptureStore
    @Environment(\.openWindow) private var openWindow
    @State private var importing = false

    var body: some View {
        Group {
            if store.recent.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "record.circle",
                                       description: Text("Your recordings are saved here automatically."))
            } else {
                List(store.recent, id: \.self) { url in
                    Button { openWindow(id: "editor", value: url) } label: {
                        Label(url.deletingPathExtension().lastPathComponent, systemImage: "film")
                            .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .toolbar {
            Button("Open Video…", systemImage: "folder") { importing = true }
            Button("Refresh", systemImage: "arrow.clockwise") { store.refreshLibrary() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url): openWindow(id: "editor", value: url)
            case .failure(let error): store.error = UserMessage(text: error.localizedDescription)
            }
        }
        .onAppear { store.refreshLibrary() }
    }
}
