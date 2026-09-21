import SwiftUI

/// One global shortcut as a Settings form row: the current keys, click to record new ones, reset.
struct RecordingShortcutView: View {
    let hotKey: RecordingHotKey
    var title = "Start / stop recording"

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button(hotKey.isListening ? "Press shortcut…" : hotKey.shortcut.label) {
                    if hotKey.isListening { hotKey.cancelListening() }
                    else { hotKey.beginListening() }
                }
                .help("Click, then press a new keyboard shortcut")
                .accessibilityLabel("\(title) shortcut")
                .accessibilityValue(hotKey.isListening ? "Listening" : hotKey.shortcut.label)
                Button {
                    hotKey.cancelListening()
                    hotKey.update(hotKey.standard)
                } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Reset to \(hotKey.standard.label)")
                .accessibilityLabel("Reset \(title) shortcut")
                .disabled(hotKey.shortcut == hotKey.standard && !hotKey.isListening)
            }
        } label: {
            Text(title)
            if hotKey.isListening {
                Text("Press Command or Control with a letter or number. Esc cancels.")
            }
            if let error = hotKey.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .onDisappear { hotKey.cancelListening() }
    }
}
