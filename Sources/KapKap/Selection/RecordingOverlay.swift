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
            panel.contentView = NSHostingView(rootView: AreaShade(hole: hole, recording: recording,
                                                                  cornerRadius: Self.cornerRadius(for: target)))
            panels.append(panel)
            CaptureOverlayTransition.show(panel)
        }
    }

    func close() {
        panels.forEach { CaptureOverlayTransition.close($0) }
        panels.removeAll()
    }

    /// A window outline has to follow the window's own rounding; an area is a plain rectangle.
    private static func cornerRadius(for target: CaptureTarget) -> CGFloat {
        guard target.windowID != nil else { return 0 }
        if #available(macOS 26.0, *) { return 16 }
        return 10
    }
}

private struct AreaShade: View {
    let hole: CGRect
    let recording: Bool
    let cornerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            if recording {
                var shade = Path(CGRect(origin: .zero, size: size))
                if !hole.isEmpty { shade.addRect(hole) }
                context.fill(shade, with: .color(.black.opacity(0.28)), style: FillStyle(eoFill: true))
            }
            guard !hole.isEmpty else { return }
            guard recording else {
                // Keep the stroke inside the window, including when its edges meet the screen bounds.
                let outline = RoundedRectangle(cornerRadius: max(0, cornerRadius - 1.5))
                    .path(in: hole.insetBy(dx: 1.5, dy: 1.5))
                context.stroke(outline, with: .color(.accentColor), lineWidth: 3)
                return
            }
            // A hairline right on the edge, so no band of shade shows between it and the recorded area.
            let edge = hole.insetBy(dx: -0.5, dy: -0.5)
            let hairline = RoundedRectangle(cornerRadius: cornerRadius > 0 ? cornerRadius + 0.5 : 0).path(in: edge)
            context.stroke(hairline, with: .color(.white.opacity(0.35)), lineWidth: 1)
            // Viewfinder corners mark the area without boxing it in; windows keep their own rounding.
            guard cornerRadius == 0 else { return }
            let corners = Self.corners(around: hole.insetBy(dx: -2, dy: -2))
            var glow = context
            glow.addFilter(.shadow(color: .black.opacity(0.45), radius: 3))
            glow.stroke(corners, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }.ignoresSafeArea().allowsHitTesting(false)
    }

    private static func corners(around rect: CGRect) -> Path {
        let arm = min(18, rect.width / 3, rect.height / 3)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}
