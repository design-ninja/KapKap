import AppKit

@MainActor
enum AppAbout {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any,
            .credits: credits
        ])
        if let content = NSApp.keyWindow?.contentView { styleLinks(in: content) }
    }

    private static let linkColor = NSColor(srgbRed: 0.55, green: 0.08, blue: 0.1, alpha: 1)

    private static func styleLinks(in view: NSView) {
        if let text = view as? NSTextView {
            text.linkTextAttributes = [.foregroundColor: linkColor, .underlineStyle: 0]
            // Selectable credits show the text cursor, so they are read-only and a click opens the link.
            text.isSelectable = false
            if !text.gestureRecognizers.contains(where: { $0.target === LinkOpener.shared }) {
                text.addGestureRecognizer(NSClickGestureRecognizer(target: LinkOpener.shared, action: #selector(LinkOpener.open(_:))))
            }
        }
        for child in view.subviews { styleLinks(in: child) }
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let text = NSMutableAttributedString(string: "Made by ", attributes: base)
        text.append(link("lirik", to: "https://lirik.pro/en", base: base))
        text.append(NSAttributedString(string: " with ♥️\n", attributes: base))
        text.append(NSAttributedString(string: "Contribute on ", attributes: base))
        text.append(link("GitHub", to: "https://github.com/design-ninja/KapKap", base: base))
        return text
    }

    private static func link(_ title: String, to url: String,
                             base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = base
        attributes[.link] = URL(string: url)!
        attributes[.foregroundColor] = linkColor
        attributes[.underlineStyle] = 0
        return NSAttributedString(string: title, attributes: attributes)
    }
}

/// Opens the link under a click in text that can no longer be selected.
@MainActor
private final class LinkOpener: NSObject {
    static let shared = LinkOpener()

    @objc func open(_ recognizer: NSClickGestureRecognizer) {
        guard let text = recognizer.view as? NSTextView, let layout = text.layoutManager,
              let container = text.textContainer, let storage = text.textStorage else { return }
        let origin = text.textContainerOrigin
        let location = recognizer.location(in: text)
        let point = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        let glyph = layout.glyphIndex(for: point, in: container)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return }
        switch storage.attribute(.link, at: index, effectiveRange: nil) {
        case let url as URL: NSWorkspace.shared.open(url)
        case let string as String: URL(string: string).map { _ = NSWorkspace.shared.open($0) }
        default: break
        }
    }
}
