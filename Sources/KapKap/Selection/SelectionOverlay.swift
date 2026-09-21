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
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.contentView = NSHostingView(rootView: SelectionView(model: model, displayID: number.uint32Value,
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
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}
