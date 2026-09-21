import AppKit

@MainActor
enum AppAbout {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any,
            .credits: credits
        ])
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
        return NSAttributedString(string: title, attributes: attributes)
    }
}
