import AppKit
import AVFoundation
import CaptureCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Recording", systemImage: "record.circle") { RecordingSettingsTab(store: store) }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings(store: store) }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var exportDirectory = ExportPreferences.directory
    @State private var loopExports = ExportPreferences.loop

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.enabled }, set: { launchAtLogin.set($0) }))
            } footer: {
                if launchAtLogin.needsApproval {
                    HStack(spacing: 4) {
                        Text("Allow KapKap in Login Items to finish turning this on.")
                        Button("Open Login Items") { launchAtLogin.openLoginItems() }.buttonStyle(.link)
                    }
                } else if let error = launchAtLogin.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Save exports to") {
                    HStack {
                        Text(FileManager.default.displayName(atPath: exportDirectory.path))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .help(exportDirectory.path)
                        Button("Choose…", action: chooseDirectory)
                    }
                }
                Toggle("Loop GIF and APNG exports", isOn: $loopExports)
            } header: {
                Text("Export")
            } footer: {
                Text("The save dialog opens in this folder. Without looping, GIF and APNG exports play once.")
            }
        }
        .toggleStyle(.switch)
        .onChange(of: loopExports) { _, loop in ExportPreferences.loop = loop }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Exports are saved here by default."
        panel.directoryURL = ExportPreferences.preparedDirectory()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            ExportPreferences.directory = url
            exportDirectory = url
        }
    }
}

private struct RecordingSettingsTab: View {
    @Bindable var store: CaptureStore
    @State private var devices: [AVCaptureDevice] = []

    var body: some View {
        Form {
            Section {
                DisplayPicker(store: store)
                Picker("Frame rate", selection: $store.settings.fps) {
                    ForEach(FrameRate.choices.reversed(), id: \.self) { Text("\($0) fps").tag($0) }
                }
                Toggle("Show cursor", isOn: $store.settings.showCursor)
                Toggle("Highlight clicks", isOn: $store.settings.highlightClicks)
            } header: {
                Text("Video")
            }
            Section {
                Toggle("System audio", isOn: $store.settings.systemAudio)
                Toggle("Microphone", isOn: $store.settings.microphone)
                if store.settings.microphone {
                    Picker("Input", selection: $store.settings.microphoneID) {
                        Text("System default").tag(String?.none)
                        ForEach(devices, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("System audio records what your Mac plays. With the microphone on too, exports mix both.")
            }
        }
        .toggleStyle(.switch)
        .disabled(store.busy)
        .onChange(of: store.settings) { _, settings in settings.save() }
        .task {
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                       mediaType: .audio, position: .unspecified).devices
        }
    }
}

private struct ShortcutSettings: View {
    let store: CaptureStore

    var body: some View {
        Form {
            Section {
                RecordingShortcutView(hotKey: store.recordingHotKey)
                RecordingShortcutView(hotKey: store.selectionHotKey, title: "Select recording area")
            } footer: {
                Text("These work in any app. Click a shortcut to change it; shortcuts that another app uses only inside itself may not be detected.")
            }
        }
    }
}
