import AppKit
import SwiftUI

/// SwiftUI draws and handles the selection. This adapter only owns desktop-spanning windows.
@MainActor
final class SelectionOverlay {
    private var panels: [NSPanel] = []
    private var escapeMonitor: Any?

    func present(completion: @escaping (CaptureTarget?) -> Void) {
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
            panel.contentView = NSHostingView(rootView: SelectionView(cancel: { [weak self] in
                self?.close()
                completion(nil)
            }) { [weak self] rect in
                let global = CGRect(x: screen.frame.minX + rect.minX,
                                    y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                self?.close()
                completion(CaptureTarget(displayID: number.uint32Value, screenFrame: screen.frame,
                                         rect: global, scale: screen.backingScaleFactor, name: "Selected area"))
            })
            panels.append(panel)
            panel.makeKeyAndOrderFront(nil)
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                completion(nil)
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

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
