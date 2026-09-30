import SwiftUI

struct RecordingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label
                .scaleEffect(pressed ? 0.95 : (hovered && enabled ? 1.15 : 1))
                // A disabled button gets no hover, so it has to look inert rather than broken.
                .opacity(enabled ? 1 : 0.4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: enabled)
                .onHover { hovered = $0 }
        }
    }
}
