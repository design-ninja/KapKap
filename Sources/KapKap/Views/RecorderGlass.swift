import SwiftUI

struct RecorderGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.clear)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.black.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    .environment(\.colorScheme, .dark)
            }
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct RecorderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconSurface(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct IconSurface<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label.font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .background(.white.opacity(pressed ? 0.16 : (hovered && enabled ? 0.09 : 0)),
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}
