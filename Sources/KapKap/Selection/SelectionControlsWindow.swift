import AppKit
import SwiftUI

/// Keep glass outside the selection overlay so its backdrop is the desktop.
struct SelectionControlsWindow<Content: View>: NSViewRepresentable {
    var hidden = false
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> Anchor {
        Anchor(content: content())
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.host.rootView = content()
        view.presentIfNeeded()
        view.setHidden(hidden)
    }

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.panel.close()
    }

    final class Anchor: NSView {
        let host: NSHostingView<Content>
        let panel: ControlsPanel
        private var positioned = false

        init(content: Content) {
            host = NSHostingView(rootView: content)
            panel = ControlsPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            super.init(frame: .zero)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host
        }

        required init?(coder: NSCoder) { fatalError("Not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            presentIfNeeded()
        }

        /// The panel sits over the desktop, so it has to step aside while an area is being drawn.
        func setHidden(_ hidden: Bool) {
            let alpha: CGFloat = hidden ? 0 : 1
            guard panel.alphaValue != alpha else { return }
            panel.ignoresMouseEvents = hidden
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = alpha
            }
        }

        func presentIfNeeded() {
            guard let window, !positioned else { return }
            positioned = true
            let size = host.fittingSize
            let screen = window.screen?.visibleFrame ?? window.frame
            panel.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.minY + 28,
                                  width: size.width, height: size.height), display: true)
            panel.orderFront(nil)
        }
    }

    final class ControlsPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}
