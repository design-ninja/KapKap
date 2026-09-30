import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum CaptureWindowGeometry {
    static func liveFrame(_ id: CGWindowID) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    /// WindowServer has a top-left origin; AppKit uses the primary display's bottom-left.
    static func screenRect(_ frame: CGRect, primary: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primary.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}
