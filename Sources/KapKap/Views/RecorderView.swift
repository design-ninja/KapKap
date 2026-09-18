import SwiftUI
import AppKit

struct RecorderView: View {
    @Bindable var store: CaptureStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showWindows = false
    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { store.selectArea() } label: { Image(systemName: "viewfinder") }
                    .help("Select area (⌘⇧2)").keyboardShortcut("2", modifiers: [.command, .shift])
                    .disabled(store.busy)

                Button { showWindows.toggle() } label: {
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

                Button {
                    Task { if store.active { await store.stop() } else { await store.start() } }
                } label: {
                    ZStack {
                        if store.phase == .starting || store.phase == .stopping {
                            ProgressView().controlSize(.small)
                        } else if store.active {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 24, height: 24)
                        } else { Circle().fill(.red).frame(width: 40, height: 40) }
                    }
                    .frame(width: 62, height: 62)
                    .contentShape(Circle())
                }
                .buttonStyle(RecordingButtonStyle())
                .disabled(store.changingPause || store.phase == .starting || store.phase == .stopping || store.phase == .selecting || store.target == nil)
                .help(store.active ? "Stop recording (\(store.recordingHotKey.shortcut.label))" : "Record (\(store.recordingHotKey.shortcut.label))")
                .accessibilityLabel(store.active ? "Stop recording" : "Start recording")

                if store.active {
                    Button { Task { await store.togglePause() } } label: {
                        Image(systemName: store.phase == .paused ? "play.fill" : "pause.fill")
                    }.help(store.phase == .paused ? "Resume" : "Pause").disabled(store.changingPause)
                } else {
                    Button { store.refreshLibrary(); openWindow(id: "recordings") } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }.help("Recent recordings")
                }
                Button { showOptions.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                }
                .help(showOptions ? "Hide recording details" : "Show recording details")
                .accessibilityLabel(showOptions ? "Hide recording details" : "Show recording details")
            }
            .buttonStyle(RecorderIconButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 10)
            if showOptions {
                VStack(spacing: 4) {
                    if store.active {
                        recordingDetails
                    } else {
                        RecordingOptionsView(settings: $store.settings) {
                            recordingDetails
                            Divider()
                        }
                        Divider()
                        HStack {
                            Button("About") { NSApp.orderFrontStandardAboutPanel(nil) }
                            Spacer()
                            Button("Quit") { NSApp.terminate(nil) }
                                .disabled(store.busy)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }
                }
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.primary)
                .padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 16)
            }
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
                }.padding(16)
            }
        }
        .background(RecorderWindowChrome(store: store))
        .background(StatusBarBridge(store: store, phase: store.phase, showRecorder: {
            openWindow(id: "recorder"); NSApp.activate(ignoringOtherApps: true)
        }, showLibrary: {
            store.refreshLibrary(); openWindow(id: "recordings"); NSApp.activate(ignoringOtherApps: true)
        }, showSettings: {
            openSettings(); NSApp.activate(ignoringOtherApps: true)
        }))
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
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

    private var recordingDetails: some View {
        HStack(spacing: 10) {
            Text("Display")
            Spacer(minLength: 12)
            Picker("Display", selection: Binding<UInt32?>(get: {
                guard let target = store.target, target.windowID == nil,
                      target.rect == target.screenFrame else { return nil }
                return target.displayID
            }, set: { displayID in
                guard let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                }) else { return }
                store.selectDisplay(screen)
            })) {
                if store.target == nil || store.target?.windowID != nil || store.hasSelectedArea {
                    Text(store.target?.name ?? "Choose a source").tag(UInt32?.none)
                }
                ForEach(NSScreen.screens, id: \.self) { screen in
                    if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                        Text(screen.localizedName).tag(Optional(id.uint32Value))
                    }
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
            .help(store.target?.name ?? "Display or window").disabled(store.busy)
        }
        .frame(minHeight: 30)
        .font(.system(size: 12))
        .controlSize(.small)
    }

    private func clock(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
