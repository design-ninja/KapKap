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
                Text("No open app windows").foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(store.windows, id: \.windowID) { window in
                            Button {
                                let selected = store.target?.windowID == window.windowID
                                store.selectWindow(window)
                                // Clearing a choice keeps the list open so the change is visible.
                                if !selected { dismiss() }
                            } label: {
                                HStack(spacing: 10) {
                                    if let pid = window.owningApplication?.processID,
                                       let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                                    } else {
                                        Image(systemName: "macwindow").frame(width: 26, height: 26)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(window.owningApplication?.applicationName ?? "Application")
                                            .font(.system(size: 13)).lineLimit(1)
                                        if let title = window.title, !title.isEmpty,
                                           title != window.owningApplication?.applicationName {
                                            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if store.target?.windowID == window.windowID {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(MenuRowStyle())
                        }
                    }.padding(5)
                }.frame(height: min(300, CGFloat(store.windows.count) * 42 + 10))
            }
        }.frame(width: 290)
        .foregroundStyle(.primary)
        .task { await store.loadWindows() }
        .onChange(of: store.needsScreenAccess) { _, needed in if needed { dismiss() } }
    }
}
