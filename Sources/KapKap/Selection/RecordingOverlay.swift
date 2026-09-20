import AppKit
import SwiftUI

@MainActor
final class RecordingOverlay {
    private var panels: [NSPanel] = []

    func show(target: CaptureTarget, recording: Bool) {
        close()
        guard !target.rect.isEmpty, target.rect != target.screenFrame else { return }
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
            if recording {
                var shade = Path(CGRect(origin: .zero, size: size))
                if !hole.isEmpty { shade.addRect(hole) }
                context.fill(shade, with: .color(.black.opacity(0.18)), style: FillStyle(eoFill: true))
            }
            guard !hole.isEmpty else { return }
            // Before recording the frame is only a marker, so it stays out of the way of the app behind it.
            let outline = RoundedRectangle(cornerRadius: recording ? 0 : 6)
                .path(in: hole.insetBy(dx: -1.5, dy: -1.5))
            context.stroke(outline, with: .color(recording ? .white.opacity(0.9) : .accentColor), lineWidth: recording ? 1 : 3)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
