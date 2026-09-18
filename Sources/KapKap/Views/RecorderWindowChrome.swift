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
        override var mouseDownCanMoveWindow: Bool { false }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }
        func configureWindow() {
            guard let window else { return }
            store?.recorderWindow = window
            window.appearance = nil
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isMovable = false
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
}
