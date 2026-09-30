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
