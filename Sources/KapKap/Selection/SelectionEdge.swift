import Foundation

enum SelectionEdge: CaseIterable {
    case left, right, top, bottom

    var horizontal: Bool { self == .left || self == .right }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        }
    }

    func resized(_ rect: CGRect, translation: CGSize, bounds: CGSize, aspectRatio: CGFloat?) -> CGRect {
        if horizontal {
            let anchor = self == .left ? rect.maxX : rect.minX
            let capacity = self == .left ? anchor : bounds.width - anchor
            var maximum = capacity
            if let aspectRatio {
                maximum = min(maximum, 2 * min(rect.midY, bounds.height - rect.midY) * aspectRatio)
            }
            let minimum = aspectRatio.map { max(16, 16 * $0) } ?? 16
            let delta = self == .left ? -translation.width : translation.width
            let width = min(maximum, max(minimum, rect.width + delta))
            let height = aspectRatio.map { width / $0 } ?? rect.height
            return CGRect(x: self == .left ? anchor - width : anchor,
                          y: rect.midY - height / 2, width: width, height: height)
        }

        let anchor = self == .top ? rect.maxY : rect.minY
        let capacity = self == .top ? anchor : bounds.height - anchor
        var maximum = capacity
        if let aspectRatio {
            maximum = min(maximum, 2 * min(rect.midX, bounds.width - rect.midX) / aspectRatio)
        }
        let minimum = aspectRatio.map { max(16, 16 / $0) } ?? 16
        let delta = self == .top ? -translation.height : translation.height
        let height = min(maximum, max(minimum, rect.height + delta))
        let width = aspectRatio.map { height * $0 } ?? rect.width
        return CGRect(x: rect.midX - width / 2,
                      y: self == .top ? anchor - height : anchor, width: width, height: height)
    }
}
