import AppKit
import SwiftUI

/// The recorder floats in a non-activating panel, like Spotlight's or Raycast's: it takes key without
/// bringing KapKap forward, and only such a panel may appear over another app's full-screen space.
final class RecorderPanel: NSPanel {
    init(store: CaptureStore) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .closable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Stay above the selection canvas, but below system menus and tooltips.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        let content = NSHostingView(rootView: RecorderView(store: store))
        contentView = content
        setContentSize(content.fittingSize)
        center()
        RecorderWindowPosition.restore(self)
        store.recorderWindow = self
    }

    /// Borderless windows refuse key by default, and a popover over a window that is not key draws
    /// every control inactive.
    override var canBecomeKey: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var nextFrame = frameRect
        if frame.width > 0, frame.size != nextFrame.size {
            nextFrame.origin.x = frame.midX - nextFrame.width / 2
            nextFrame = constrainFrameRect(nextFrame, to: screen)
        }
        super.setFrame(nextFrame, display: flag)
    }

    /// Ignores the menu bar and Dock, keeping the panel only inside the physical screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let bounds = (screen ?? self.screen ?? NSScreen.main)?.frame else { return frameRect }
        var rect = frameRect
        rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return rect
    }
}

/// A popover opens in its own window, which macOS keeps off another app's full-screen space unless it
/// is non-activating and joins every space, like the panel it belongs to.
struct FullScreenAuxiliary: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            (window as? NSPanel)?.styleMask.insert(.nonactivatingPanel)
        }
    }
}
