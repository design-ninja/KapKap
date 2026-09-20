import AppKit

@MainActor
enum AppAbout {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any
        ])
    }
}
