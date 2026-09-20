import SwiftUI

struct RecorderGlass: ViewModifier {
    var cornerRadius: CGFloat = 20

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.clear)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.black.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    .environment(\.colorScheme, .dark)
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.12)))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.12)))
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
