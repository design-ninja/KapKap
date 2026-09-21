import SwiftUI
import AppKit

struct RecorderView: View {
    @Bindable var store: CaptureStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showWindows = false
    @State private var showOptions = false
    @FocusState private var dimension: SelectionControlsView.Dimension?
    @Namespace private var panel
    private var selecting: Bool { store.phase == .selecting }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if selecting {
                    SelectionControlsView(store: store, model: store.selectionModel,
                                          focus: $dimension, side: .leading)
                } else {
                    Button { store.selectArea() } label: { Image(systemName: "viewfinder") }
                        .help("Select area (⌘⇧2)").keyboardShortcut("2", modifiers: [.command, .shift])
                        .disabled(store.busy)

                    Button { focusPanel(); showWindows.toggle() } label: {
                        Image(systemName: "macwindow")
                            .foregroundStyle(.white)
                    }
                    .help("Choose a window").accessibilityLabel("Choose a window")
                    .disabled(store.busy)
                    .popover(isPresented: $showWindows, arrowEdge: .bottom) {
                        WindowPickerView(store: store)
                            .foregroundStyle(.primary)
                            .buttonStyle(.automatic)
                    }
                }

                RecordButton(store: store, action: record)
                    .matchedGeometryEffect(id: "record", in: panel, properties: .position)
                    .disabled(recordDisabled)
                    .help(recordHelp)
                    .accessibilityLabel(store.active ? "Stop recording" : "Start recording")

                if selecting {
                    SelectionControlsView(store: store, model: store.selectionModel,
                                          focus: $dimension, side: .trailing)
                } else {
                    if store.active {
                        Button { Task { await store.togglePause() } } label: {
                            Image(systemName: store.phase == .paused ? "play.fill" : "pause.fill")
                        }.help(store.phase == .paused ? "Resume" : "Pause").disabled(store.changingPause)
                    } else {
                        Button { store.refreshLibrary(); openWindow(id: "recordings") } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }.help("Recent recordings")
                    }
                    Button { focusPanel(); showOptions.toggle() } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.white)
                    }
                    .help(showOptions ? "Hide recording details" : "Show recording details")
                    .accessibilityLabel(showOptions ? "Hide recording details" : "Show recording details")
                    // A popover keeps the panel one size and lets AppKit place the details on screen,
                    // wherever the panel floats — inline details ran off the edge near the Dock.
                    .popover(isPresented: $showOptions, arrowEdge: .bottom) { options }
                }
            }
            .buttonStyle(RecorderIconButtonStyle())
            .padding(.horizontal, 12).padding(.vertical, 5)
            if store.needsScreenAccess {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Allow Screen Recording", systemImage: "lock.shield").fontWeight(.medium)
                    Text("Enable KapKap in Privacy & Security, then reopen the app to start recording.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Open Settings") { CapturePermissions.openSettings() }
                        Button("Reopen KapKap") { CapturePermissions.relaunch() }
                    }
                }.padding(16).frame(width: 308, alignment: .leading)
            }
        }
        .background(RecorderWindowChrome(store: store, hidden: store.selectionModel.interacting))
        // A popover over an unfocused panel renders its controls inactive, so take focus first.
        .onChange(of: showOptions) { _, shown in if shown { focusPanel() } }
        .onChange(of: showWindows) { _, shown in if shown { focusPanel() } }
        .background(StatusBarBridge(store: store, phase: store.phase, showRecorder: {
            openWindow(id: "recorder"); NSApp.activate(ignoringOtherApps: true)
        }, showLibrary: {
            store.refreshLibrary(); openWindow(id: "recordings"); NSApp.activate(ignoringOtherApps: true)
        }, showSettings: {
            openSettings(); NSApp.activate(ignoringOtherApps: true)
        }))
        // Both states size to their own controls, so the edge padding reads the same in each.
        .fixedSize(horizontal: true, vertical: true)
        .animation(.snappy(duration: 0.22), value: selecting)
        .modifier(RecorderGlass())
        .contentShape(Rectangle())
        .modifier(RecorderWindowDrag(store: store))
        .alert("KapKap", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
            Button("Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        } message: { Text(store.error?.text ?? "") }
        .task(id: store.latestRecording) {
            if let url = store.latestRecording {
                openWindow(id: "editor", value: url)
                store.latestRecording = nil
            }
        }
    }

    private func focusPanel() {
        NSApp.activate(ignoringOtherApps: true)
        store.recorderWindow?.makeKeyAndOrderFront(nil)
    }

    private func record() {
        guard selecting else {
            Task { if store.active { await store.stop() } else { await store.start() } }
            return
        }
        if dimension == .height { store.selectionModel.commitHeight() }
        else if dimension == .width { store.selectionModel.commitWidth() }
        dimension = nil
        store.startSelectedArea()
    }

    private var recordDisabled: Bool {
        if selecting { return !store.selectionModel.ready }
        return store.changingPause || store.phase == .starting || store.phase == .stopping || store.target == nil
    }

    private var recordHelp: String {
        if selecting { return "Start recording the selected area" }
        return store.active ? "Stop recording (\(store.recordingHotKey.shortcut.label))"
                            : "Record (\(store.recordingHotKey.shortcut.label))"
    }

    private var options: some View {
        VStack(spacing: 4) {
            if store.active {
                CaptureSourceView(store: store)
            } else {
                RecordingOptionsView(settings: $store.settings) {
                    CaptureSourceView(store: store)
                    Divider()
                }
                Divider().padding(.vertical, 4)
                VStack(spacing: 1) {
                    menuRow("About") { AppAbout.show() }
                    menuRow("Quit") { NSApp.terminate(nil) }.disabled(store.busy)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 300)
        .foregroundStyle(.primary)
    }

    private func menuRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12))
                .padding(.horizontal, 6).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(MenuRowStyle())
            // The highlight reaches into the margin so the title lines up with the option labels.
            .padding(.horizontal, -6)
    }

}
