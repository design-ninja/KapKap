import Foundation

public enum CaptureGeometry {
    /// AppKit has a bottom-left origin; ScreenCaptureKit source rectangles are display-local, top-left.
    public static func sourceRect(selection: CGRect, screen: CGRect) -> CGRect {
        let clipped = selection.standardized.intersection(screen)
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }

    public static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(2, floor(points.width * scale / 2) * 2),
               height: max(2, floor(points.height * scale / 2) * 2))
    }

    /// Crop inward to the encoder's two-pixel grid instead of resizing a fractional source.
    public static func pixelAlignedRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale.isFinite, scale > 0, !rect.isNull, !rect.isEmpty else { return .zero }
        let left = ceil(rect.minX * scale / 2) * 2
        let top = ceil(rect.minY * scale / 2) * 2
        let right = floor(rect.maxX * scale / 2) * 2
        let bottom = floor(rect.maxY * scale / 2) * 2
        guard right > left, bottom > top else { return .zero }
        return CGRect(x: left / scale, y: top / scale,
                      width: (right - left) / scale, height: (bottom - top) / scale)
    }
}
