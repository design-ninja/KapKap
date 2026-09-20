import SwiftUI
import AppKit

/// Routes a close request back to SwiftUI so an unexported recording can ask before it disappears.
@MainActor
enum EditorCloseCoordinator {
    private static var handlers: [ObjectIdentifier: () -> Bool] = [:]

    static func register(_ window: NSWindow, handler: @escaping () -> Bool) {
        handlers[ObjectIdentifier(window)] = handler
    }

    static func unregister(_ window: NSWindow) {
        handlers.removeValue(forKey: ObjectIdentifier(window))
    }

    /// True when the editor took over the close and will finish it itself.
    static func intercept(_ window: NSWindow) -> Bool {
        handlers[ObjectIdentifier(window)]?() ?? false
    }
}

struct EditorWindowLayout: NSViewRepresentable {
    let url: URL
    let aspectRatio: Double?
    let closeRequest: () -> Bool

    private static let barHeight: CGFloat = 56

    func makeNSView(context: Context) -> LayoutView { LayoutView() }

    func updateNSView(_ view: LayoutView, context: Context) {
        view.url = url
        view.aspectRatio = aspectRatio
        view.closeRequest = closeRequest
        view.applyLayout()
    }

    static func dismantleNSView(_ view: LayoutView, coordinator: ()) {
        view.unregister()
    }

    final class LayoutView: NSView {
        var url: URL?
        var aspectRatio: Double?
        var closeRequest: (() -> Bool)?
        private var didSize = false
        private var didStyle = false
        private var closing = false
        private weak var registered: NSWindow?

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyLayout() }

        func unregister() {
            registered.map(EditorCloseCoordinator.unregister)
            registered = nil
        }

        func applyLayout() {
            guard let window, let url else { return }
            window.title = url.deletingPathExtension().lastPathComponent
            window.representedURL = url
            if registered !== window {
                unregister()
                registered = window
                EditorCloseCoordinator.register(window) { [weak self] in self?.closeRequest?() ?? false }
            }
            if !didStyle {
                didStyle = true
                // A dark window keeps the title bar, popovers and menus in the editor's own palette.
                window.appearance = NSAppearance(named: .darkAqua)
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .black
                if let close = window.standardWindowButton(.closeButton) {
                    close.target = self
                    close.action = #selector(requestClose)
                }
            }
            guard !didSize, let aspectRatio, aspectRatio > 0 else { return }
            didSize = true
            let screen = window.screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
            let maxHeight = max(340, screen.height - 100)
            let width = min(1100, max(820, (maxHeight - EditorWindowLayout.barHeight) * aspectRatio))
            let height = min(maxHeight, max(340, width / aspectRatio + EditorWindowLayout.barHeight))
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
        }

        @objc private func requestClose() {
            // performClose() would click this very button again, so the window is closed directly.
            guard !closing, closeRequest?() != true else { return }
            closing = true
            window?.close()
        }
    }
}
