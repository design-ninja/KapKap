import SwiftUI
import AppKit

struct RecorderWindowChrome: NSViewRepresentable {
    var hidden = false

    func makeNSView(context: Context) -> DragSurface { DragSurface() }

    func updateNSView(_ view: DragSurface, context: Context) {
        view.setHidden(hidden)
    }

    final class DragSurface: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

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
