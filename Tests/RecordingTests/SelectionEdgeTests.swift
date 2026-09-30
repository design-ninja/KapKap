import XCTest
@testable import KapKap

final class SelectionEdgeTests: XCTestCase {
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
    private let bounds = CGSize(width: 500, height: 400)

    func testFreeResizeChangesOnlyDraggedSide() {
        let translation = CGSize(width: 40, height: 30)
        let expected: [(SelectionEdge, CGRect)] = [
            (.left, CGRect(x: 140, y: 100, width: 160, height: 100)),
            (.right, CGRect(x: 100, y: 100, width: 240, height: 100)),
            (.top, CGRect(x: 100, y: 130, width: 200, height: 70)),
            (.bottom, CGRect(x: 100, y: 100, width: 200, height: 130))
        ]
        for (edge, result) in expected {
            XCTAssertEqual(edge.resized(rect, translation: translation, bounds: bounds, aspectRatio: nil), result)
        }
    }

    func testEverySideStopsAtDisplayBoundary() {
        let expected: [(SelectionEdge, CGSize, CGRect)] = [
            (.left, CGSize(width: -1000, height: 0), CGRect(x: 0, y: 100, width: 300, height: 100)),
            (.right, CGSize(width: 1000, height: 0), CGRect(x: 100, y: 100, width: 400, height: 100)),
            (.top, CGSize(width: 0, height: -1000), CGRect(x: 100, y: 0, width: 200, height: 200)),
            (.bottom, CGSize(width: 0, height: 1000), CGRect(x: 100, y: 100, width: 200, height: 300))
        ]
        for (edge, translation, result) in expected {
            XCTAssertEqual(edge.resized(rect, translation: translation, bounds: bounds, aspectRatio: nil), result)
        }
    }

    func testDraggedSideCannotCrossOppositeSide() {
        for edge in SelectionEdge.allCases {
            let sign: CGFloat = edge == .left || edge == .top ? 1 : -1
            let resized = edge.resized(rect, translation: CGSize(width: sign * 1000, height: sign * 1000),
                                       bounds: bounds, aspectRatio: nil)
            XCTAssertEqual(edge.horizontal ? resized.width : resized.height, 16)
            switch edge {
            case .left: XCTAssertEqual(resized.maxX, rect.maxX)
            case .right: XCTAssertEqual(resized.minX, rect.minX)
            case .top: XCTAssertEqual(resized.maxY, rect.maxY)
            case .bottom: XCTAssertEqual(resized.minY, rect.minY)
            }
        }
    }

    func testLockedResizePreservesRatioAndOppositeSideWithinDisplay() {
        for edge in SelectionEdge.allCases {
            let sign: CGFloat = edge == .left || edge == .top ? -1 : 1
            let resized = edge.resized(rect, translation: CGSize(width: sign * 1000, height: sign * 1000),
                                       bounds: bounds, aspectRatio: 2)
            XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.0001)
            XCTAssertTrue(CGRect(origin: .zero, size: bounds).contains(resized))
            if edge.horizontal { XCTAssertEqual(resized.midY, rect.midY) }
            else { XCTAssertEqual(resized.midX, rect.midX) }
            switch edge {
            case .left: XCTAssertEqual(resized.maxX, rect.maxX)
            case .right: XCTAssertEqual(resized.minX, rect.minX)
            case .top: XCTAssertEqual(resized.maxY, rect.maxY)
            case .bottom: XCTAssertEqual(resized.minY, rect.minY)
            }
        }
    }
}
