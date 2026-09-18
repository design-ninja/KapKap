import AppKit
import SwiftUI

@MainActor
final class RecordingOverlay {
    private var panels: [NSPanel] = []

    func show(target: CaptureTarget, recording: Bool) {
        close()
        guard target.windowID == nil, target.rect != target.screenFrame else { return }
        for screen in NSScreen.screens {
            let intersection = target.rect.intersection(screen.frame)
            let hole = intersection.isNull ? CGRect.zero : CGRect(
                x: intersection.minX - screen.frame.minX,
                y: screen.frame.maxY - intersection.maxY,
                width: intersection.width, height: intersection.height)
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: AreaShade(hole: hole, recording: recording))
            panels.append(panel)
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

private struct AreaShade: View {
    let hole: CGRect
    let recording: Bool

    var body: some View {
        Canvas { context, size in
            var shade = Path(CGRect(origin: .zero, size: size))
            if !hole.isEmpty { shade.addRect(hole) }
            context.fill(shade, with: .color(.black.opacity(recording ? 0.18 : 0.45)), style: FillStyle(eoFill: true))
            if !hole.isEmpty {
                context.stroke(Path(hole.insetBy(dx: -1, dy: -1)), with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
