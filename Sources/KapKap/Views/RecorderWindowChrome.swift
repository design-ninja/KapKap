import SwiftUI
import AppKit

struct RecorderWindowChrome: NSViewRepresentable {
    let store: CaptureStore
    var hidden = false

    func makeNSView(context: Context) -> DragSurface {
        let view = DragSurface()
        view.store = store
        return view
    }

    func updateNSView(_ view: DragSurface, context: Context) {
        view.configureWindow()
        view.setHidden(hidden)
    }

    final class DragSurface: NSView {
        weak var store: CaptureStore?
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
            // No inset: a panel parked against the Dock or menu bar must not be nudged inward
            // just because swapping controls resized it.
            let visible = screen.visibleFrame
            let frame = window.frame
            var origin = frame.origin
            origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
            if origin != frame.origin { window.setFrameOrigin(origin) }
        }
        func configureWindow() {
            guard let window else { return }
            store?.recorderWindow = window
            window.appearance = NSAppearance(named: .darkAqua)
            // A borderless window can never become key, and a popover over a window that is not
            // key draws every control inactive. Titled (with the bar hidden) can take key.
            if let panel = window as? NSPanel {
                panel.styleMask.remove(.nonactivatingPanel)
                panel.becomesKeyOnlyIfNeeded = false
            }
            window.styleMask.insert([.titled, .fullSizeContentView, .closable])
            // Changing the style mask restores the system background, so clear it afterwards.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.standardWindowButton(.closeButton)?.isEnabled = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isMovable = false
            if resizeObserver == nil {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.keepOnScreen() }
                    }
            }
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
}
