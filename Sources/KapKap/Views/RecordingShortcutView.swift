import SwiftUI

struct RecordingShortcutView: View {
    let hotKey: RecordingHotKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start / stop recording")
                Spacer(minLength: 12)
                Button(hotKey.isListening ? "Press shortcut…" : hotKey.shortcut.label) {
                    if hotKey.isListening { hotKey.cancelListening() }
                    else { hotKey.beginListening() }
                }
                .help("Click, then press a new keyboard shortcut")
                .accessibilityLabel("Recording shortcut")
                .accessibilityValue(hotKey.isListening ? "Listening" : hotKey.shortcut.label)
                Button {
                    hotKey.cancelListening()
                    hotKey.update(.standard)
                } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Reset to ⌃⌥⌘R")
                .disabled(hotKey.shortcut == .standard && !hotKey.isListening)
            }.frame(minHeight: 30)
            Text(hotKey.isListening ? "Press Command or Control with a letter or number. Esc cancels." :
                 "Works across apps. Click the shortcut to change it.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = hotKey.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Shortcuts used only inside other apps may not be detected.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 12)).controlSize(.small)
        .onDisappear { hotKey.cancelListening() }
    }
}
