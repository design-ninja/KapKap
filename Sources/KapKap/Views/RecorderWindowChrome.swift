import SwiftUI
import AppKit

struct RecorderWindowChrome: NSViewRepresentable {
    var hidden = false

    func makeNSView(context: Context) -> DragSurface { DragSurface() }

    func updateNSView(_ view: DragSurface, context: Context) {
        view.configureWindow()
        view.setHidden(hidden)
    }

    final class DragSurface: NSView {
        private var resizeObserver: NSObjectProtocol?
        override var mouseDownCanMoveWindow: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }

        /// The panel sits over the desktop, so it steps aside while an area is being drawn.
        func setHidden(_ hidden: Bool) {
            guard let window else { return }
            let alpha: CGFloat = hidden ? 0 : 1
            guard window.alphaValue != alpha else { return }
            window.ignoresMouseEvents = hidden
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window.animator().alphaValue = alpha
            }
        }

        /// The panel floats wherever it was dropped, so anything that grows it has to stay reachable.
        private func keepOnScreen() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.frame
            let frame = window.frame
            var origin = frame.origin
            origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
            if origin != frame.origin { window.setFrameOrigin(origin) }
        }

        func configureWindow() {
            guard let window, resizeObserver == nil else { return }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.keepOnScreen() }
                }
        }
    }
}

/// Where the user last dropped the panel, kept across launches.
enum RecorderWindowPosition {
    private static let key = "recorderWindowOrigin"

    static func save(_ origin: CGPoint) {
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: key)
    }

    static func load() -> CGPoint? {
        UserDefaults.standard.string(forKey: key).map(NSPointFromString)
    }

    /// Puts the panel back where it was left last time, as long as that spot is still on a screen.
    static func restore(_ window: NSWindow) {
        guard let origin = load() else { return }
        let frame = NSRect(origin: origin, size: window.frame.size)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return }
        window.setFrameOrigin(origin)
        window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: false)
    }
}
