import SwiftUI

/// One control vocabulary for the dark surfaces: editor bar, playback HUD and selection panel.
enum ControlSurface {
    static let height: CGFloat = 28
    static let radius: CGFloat = 8
    static let fill = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.12)
}

/// Groups related controls into a single rounded field so a bar reads as units instead of loose parts.
struct FieldSurface<Content: View>: View {
    var spacing: CGFloat = 3
    var padding: CGFloat = 4
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: spacing) { content() }
            .padding(.horizontal, padding)
            .frame(height: ControlSurface.height)
            .background(ControlSurface.fill, in: RoundedRectangle(cornerRadius: ControlSurface.radius))
            .overlay(RoundedRectangle(cornerRadius: ControlSurface.radius).strokeBorder(ControlSurface.border))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Numeric entry without the platform bezel, which does not survive on a dark bar.
struct FieldText: ViewModifier {
    var width: CGFloat
    var focused = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: width, height: 22)
            .background(focused ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 1))
    }
}

struct GlyphButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var glyph: CGFloat = 13
    var radius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed, size: size, glyph: glyph, radius: radius)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        let size: CGFloat
        let glyph: CGFloat
        let radius: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label.font(.system(size: glyph, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.3))
                .frame(width: size, height: size)
                .background(Color.white.opacity(pressed ? 0.2 : (hovered && enabled ? 0.11 : 0)),
                            in: RoundedRectangle(cornerRadius: radius))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

/// A chevron that opens a menu inside a field, so presets stay attached to the value they change.
struct ChevronMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Menu { content() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.6 : 0.25))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .background(Color.white.opacity(hovered && enabled ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 5))
        .onHover { hovered = $0 }
    }
}

/// A value plus chevron that reads as one field rather than a platform pop-up button.
/// The surface sits outside the menu: a borderless menu does not draw its label's background.
struct MenuField<Content: View>: View {
    let title: String
    var width: CGFloat?
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Menu { content() } label: {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
            .padding(.horizontal, 9)
            .frame(width: width, height: ControlSurface.height)
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .background(hovered && enabled ? Color.white.opacity(0.14) : ControlSurface.fill,
                    in: RoundedRectangle(cornerRadius: ControlSurface.radius))
        .overlay(RoundedRectangle(cornerRadius: ControlSurface.radius).strokeBorder(ControlSurface.border))
        .onHover { hovered = $0 }
    }
}

/// Half of the split export control: the action keeps the leading corners, the menu the trailing ones.
struct SplitActionStyle: ButtonStyle {
    var leading = true

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed, leading: leading)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        let leading: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label.foregroundStyle(.white)
                .background(Color.white.opacity(pressed ? 0.22 : (hovered && enabled ? 0.13 : 0)), in: shape)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }

        private var shape: UnevenRoundedRectangle {
            UnevenRoundedRectangle(topLeadingRadius: leading ? ControlSurface.radius : 0,
                                   bottomLeadingRadius: leading ? ControlSurface.radius : 0,
                                   bottomTrailingRadius: leading ? 0 : ControlSurface.radius,
                                   topTrailingRadius: leading ? 0 : ControlSurface.radius)
        }
    }
}

/// A full-width row that reads like a menu item: used by the window picker and the panel's popover.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Row<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label.opacity(enabled ? 1 : 0.4)
                // Nested rounding: the row follows the popover's radius less its inset.
                .background(Color.primary.opacity(pressed || (hovered && enabled) ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 9))
                .onHover { hovered = $0 }
        }
    }
}
