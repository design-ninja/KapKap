import AppKit
import SwiftUI

/// SwiftUI draws and handles the selection. This adapter only owns desktop-spanning windows.
@MainActor
final class SelectionOverlay {
    private var panels: [NSPanel] = []
    private var escapeMonitor: Any?

    func present(model: SelectionModel, onCancel: @escaping () -> Void) {
        close()
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.contentView = NSHostingView(rootView: SelectionView(model: model, displayID: displayID,
                                                                      screenFrame: screen.frame,
                                                                      scale: screen.backingScaleFactor))
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                onCancel()
                return nil
            }
            return event
        }
        // Only the active app may set the cursor, and the crosshair is the whole point. The panels are
        // already on the current space, so activating does not leave another app's full screen.
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        panels.forEach { $0.close() }
        panels.removeAll()
        NSCursor.arrow.set()
    }
}

/// Never key: clicking the canvas must not take hover tracking and field focus off the panel.
/// Non-activating, like the recorder panel, so it can cover another app's full-screen space.
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}
