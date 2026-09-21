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
        private var showObserver: NSObjectProtocol?
        private var restored = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        deinit {
            for observer in [resizeObserver, showObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func restoreOnce() {
            restored = true
            if let showObserver { NotificationCenter.default.removeObserver(showObserver) }
            showObserver = nil
            restoreOrigin()
        }

        /// Puts the panel back where it was left last time, as long as that spot is still on a screen.
        private func restoreOrigin() {
            guard let window, let origin = RecorderWindowPosition.load() else { return }
            let frame = NSRect(origin: origin, size: window.frame.size)
            guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
            window.setFrameOrigin(origin)
            keepOnScreen()
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
            // SwiftUI centers the window as it orders it in, so the saved spot is applied only once it shows.
            if !restored, window.occlusionState.contains(.visible) {
                restoreOnce()
            } else if showObserver == nil, !restored {
                showObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
                            self.restoreOnce()
                        }
                    }
            }
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
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
}
