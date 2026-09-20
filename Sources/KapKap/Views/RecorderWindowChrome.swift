import SwiftUI
import AppKit

struct RecorderWindowChrome: NSViewRepresentable {
    let store: CaptureStore
    func makeNSView(context: Context) -> DragSurface {
        let view = DragSurface()
        view.store = store
        return view
    }
    func updateNSView(_ view: DragSurface, context: Context) { view.configureWindow() }

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

        /// The panel floats wherever it was dropped, so anything that grows it has to stay reachable.
        private func keepOnScreen() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let frame = window.frame
            var origin = frame.origin
            origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
            if origin != frame.origin { window.setFrameOrigin(origin) }
        }
        func configureWindow() {
            guard let window else { return }
            store?.recorderWindow = window
            window.appearance = nil
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.closable)
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
