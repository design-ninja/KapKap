import AppKit
import SwiftUI

/// Draws and edits the area on one display; the controls for it live in the recorder panel.
struct SelectionView: View {
    @Bindable var model: SelectionModel
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let scale: CGFloat
    @State private var pointer: CGPoint?
    @State private var dragOrigin: CGRect?
    @State private var moving = false
    @State private var resizeAnchor: CGPoint?
    @State private var resizeCorner: Int?
    @State private var resizeEdge: SelectionEdge?

    private var mine: Bool { model.displayID == displayID }
    private var selection: CGRect { mine ? model.rect : .zero }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    var shade = Path(CGRect(origin: .zero, size: size))
                    if !selection.isEmpty { shade.addRect(selection) }
                    context.fill(shade, with: .color(.black.opacity(0.35)), style: FillStyle(eoFill: true))
                    if !selection.isEmpty {
                        context.stroke(Path(selection), with: .color(.white), lineWidth: 1)
                        for point in corners(selection) + SelectionEdge.allCases.map({ $0.point(in: selection) }) {
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                                         with: .color(.white))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { drag in updateDrag(drag, bounds: geometry.size) }
                    .onEnded { _ in
                        dragOrigin = nil
                        resizeAnchor = nil
                        resizeCorner = nil
                        resizeEdge = nil
                        pointer = nil
                        model.interacting = false
                        model.syncFields()
                        NSCursor.arrow.set()
                    })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        guard dragOrigin == nil else { return }
                        if selection.isEmpty { pointer = point }
                        if let corner = corner(at: point, in: selection) {
                            cornerCursor(corner).set()
                        } else if let edge = edge(at: point, in: selection) {
                            edgeCursor(edge).set()
                        } else if selection.contains(point) { NSCursor.openHand.set() }
                        else { NSCursor.crosshair.set() }
                    case .ended: pointer = nil; NSCursor.arrow.set()
                    }
                }
                if !model.hasArea {
                    Text("Drag to select · Esc to cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                        .position(x: geometry.size.width / 2, y: 54)
                        .allowsHitTesting(false)
                }
                if let pointer {
                    Text(selection.isEmpty ? "\(Int(pointer.x)), \(Int(pointer.y))"
                                           : "\(Int(selection.width)) × \(Int(selection.height))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
                        .position(x: min(pointer.x + 55, geometry.size.width - 60),
                                  y: min(pointer.y + 18, geometry.size.height - 16))
                        .allowsHitTesting(false)
                }
            }
        }.ignoresSafeArea()
    }

    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func updateDrag(_ drag: DragGesture.Value, bounds: CGSize) {
        model.interacting = true
        if dragOrigin == nil {
            model.activate(displayID: displayID, screenFrame: screenFrame, scale: scale, bounds: bounds)
            dragOrigin = model.rect
            if let index = corner(at: drag.startLocation, in: model.rect) {
                resizeCorner = index
                resizeAnchor = corners(model.rect)[3 - index]
            }
            if resizeAnchor == nil { resizeEdge = edge(at: drag.startLocation, in: model.rect) }
            moving = resizeAnchor == nil && resizeEdge == nil && model.rect.contains(drag.startLocation)
        }
        guard let original = dragOrigin else { return }
        if moving {
            model.rect.origin = CGPoint(x: max(0, min(bounds.width - original.width, original.minX + drag.translation.width)),
                                        y: max(0, min(bounds.height - original.height, original.minY + drag.translation.height)))
            NSCursor.closedHand.set()
        } else if let resizeEdge {
            let proportion = model.locked
                ? model.aspect(model.ratio).map { CGFloat($0) } ?? (original.height > 0 ? original.width / original.height : nil)
                : nil
            model.rect = resizeEdge.resized(original, translation: drag.translation, bounds: bounds, aspectRatio: proportion)
            pointer = drag.location
            edgeCursor(resizeEdge).set()
        } else {
            let start = resizeAnchor ?? drag.startLocation
            let end = CGPoint(x: max(0, min(bounds.width, drag.location.x)), y: max(0, min(bounds.height, drag.location.y)))
            var w = abs(end.x - start.x)
            var h = abs(end.y - start.y)
            if model.locked, let proportion = model.aspect(model.ratio) ?? (original.height > 0 ? original.width / original.height : nil) {
                w = min(w, h * proportion)
                h = w / proportion
            }
            model.rect = CGRect(x: end.x < start.x ? start.x - w : start.x,
                                y: end.y < start.y ? start.y - h : start.y, width: w, height: h)
            pointer = end
            if resizeCorner != nil {
                let corner = (end.y < start.y ? 0 : 2) + (end.x < start.x ? 0 : 1)
                cornerCursor(corner).set()
            }
        }
        model.syncFields()
    }

    private func edge(at point: CGPoint, in rect: CGRect) -> SelectionEdge? {
        guard !rect.isEmpty else { return nil }
        return SelectionEdge.allCases.first {
            let handle = $0.point(in: rect)
            return hypot(handle.x - point.x, handle.y - point.y) < 12
        }
    }

    private func corner(at point: CGPoint, in rect: CGRect) -> Int? {
        guard !rect.isEmpty else { return nil }
        return corners(rect).firstIndex { hypot($0.x - point.x, $0.y - point.y) < 12 }
    }

    private func cornerCursor(_ index: Int) -> NSCursor {
        let positions: [NSCursor.FrameResizePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        return NSCursor.frameResize(position: positions[index], directions: .all)
    }

    private func edgeCursor(_ edge: SelectionEdge) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch edge {
        case .left: position = .left
        case .right: position = .right
        case .top: position = .top
        case .bottom: position = .bottom
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}
