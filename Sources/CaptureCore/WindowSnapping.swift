import Foundation

public struct WindowSnapping {
    public private(set) var anchor: CGPoint?
    public init() {}

    public mutating func reset() { anchor = nil }

    public mutating func origin(for proposed: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let center = CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        if let anchor {
            if hypot(proposed.x - anchor.x, proposed.y - anchor.y) <= (anchor == center ? 40 : 32) { return anchor }
            self.anchor = nil
            return proposed
        }
        let points = [
            center,
            CGPoint(x: center.x, y: visibleFrame.minY),
            CGPoint(x: center.x, y: visibleFrame.maxY - size.height),
            CGPoint(x: visibleFrame.minX, y: center.y),
            CGPoint(x: visibleFrame.maxX - size.width, y: center.y)
        ]
        if let nearest = points.min(by: {
            hypot(proposed.x - $0.x, proposed.y - $0.y) < hypot(proposed.x - $1.x, proposed.y - $1.y)
        }), hypot(proposed.x - nearest.x, proposed.y - nearest.y) <= (nearest == center ? 28 : 14) {
            anchor = nearest
            return nearest
        }
        return proposed
    }
}
