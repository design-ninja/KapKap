import SwiftUI
import AppKit

struct WindowPickerView: View {
    @Bindable var store: CaptureStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.isLoadingWindows {
                ProgressView("Loading windows…").frame(maxWidth: .infinity, minHeight: 80)
            } else if store.windows.isEmpty {
                Text("No windows available").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.windows, id: \.windowID) { window in
                            Button {
                                store.selectWindow(window)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    if let pid = window.owningApplication?.processID,
                                       let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "macwindow").frame(width: 24, height: 24)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(window.owningApplication?.applicationName ?? "Application")
                                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(window.title ?? "Untitled window")
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if store.target?.windowID == window.windowID {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(WindowChoiceStyle())
                        }
                    }.padding(5)
                }.frame(height: min(280, CGFloat(store.windows.count) * 48 + 10))
            }
            Divider()
            HStack {
                Text("Choose a window").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.loadWindows() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh windows").accessibilityLabel("Refresh windows")
                    .disabled(store.isLoadingWindows)
            }.padding(10)
        }.frame(width: 290)
        .foregroundStyle(.primary)
        .task { await store.loadWindows() }
        .onChange(of: store.needsScreenAccess) { _, needed in if needed { dismiss() } }
    }
}

private struct WindowChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WindowChoiceRow(pressed: configuration.isPressed, content: configuration.label)
    }

    private struct WindowChoiceRow<Content: View>: View {
        let pressed: Bool
        let content: Content
        @State private var hovered = false
        var body: some View {
            content.background(pressed || hovered ? Color.primary.opacity(0.08) : .clear,
                               in: RoundedRectangle(cornerRadius: 5))
                .onHover { hovered = $0 }
        }
    }
}
