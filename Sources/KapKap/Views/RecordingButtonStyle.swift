import SwiftUI

struct RecordingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            label
                .scaleEffect(enabled ? (pressed ? 0.95 : (hovered ? 1.15 : 1)) : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
                .onHover { hovered = $0 }
        }
    }
}
