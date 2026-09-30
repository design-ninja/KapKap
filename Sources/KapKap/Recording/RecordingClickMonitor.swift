import AppKit
import CoreMedia

@MainActor
final class RecordingClickMonitor {
    private var monitor: Any?
    var paused = false

    init(target: CaptureTarget, source: CGRect, sink: SampleWriter) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak sink] _ in
            MainActor.assumeIsolated {
                guard let self, !self.paused, let sink else { return }
                let frame: CGRect
                if let windowID = target.windowID {
                    guard let bounds = CaptureWindowGeometry.liveFrame(windowID),
                          let primary = NSScreen.screens.first else { return }
                    let window = CaptureWindowGeometry.screenRect(bounds, primary: primary.frame)
                    frame = CGRect(x: window.minX + source.minX, y: window.maxY - source.maxY,
                                   width: source.width, height: source.height)
                } else {
                    frame = CGRect(x: target.screenFrame.minX + source.minX,
                                   y: target.screenFrame.maxY - source.maxY,
                                   width: source.width, height: source.height)
                }
                guard let point = Self.normalizedPoint(NSEvent.mouseLocation, in: frame) else { return }
                sink.highlightClick(at: point, time: CMClockGetTime(CMClockGetHostTimeClock()))
            }
        }
    }

    static func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> CGPoint? {
        guard !frame.isEmpty, frame.contains(point) else { return nil }
        return CGPoint(x: (point.x - frame.minX) / frame.width, y: (frame.maxY - point.y) / frame.height)
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
