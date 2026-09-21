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
                        for point in corners(selection) {
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
                        pointer = nil
                        model.interacting = false
                        model.syncFields()
                        NSCursor.arrow.set()
                    })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if selection.isEmpty { pointer = point }
                        if selection.contains(point) { NSCursor.openHand.set() }
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
            let points = corners(model.rect)
            if !model.rect.isEmpty,
               let index = points.firstIndex(where: { hypot($0.x - drag.startLocation.x, $0.y - drag.startLocation.y) < 12 }) {
                resizeAnchor = points[3 - index]
            }
            moving = resizeAnchor == nil && model.rect.contains(drag.startLocation)
        }
        guard let original = dragOrigin else { return }
        if moving {
            model.rect.origin = CGPoint(x: max(0, min(bounds.width - original.width, original.minX + drag.translation.width)),
                                        y: max(0, min(bounds.height - original.height, original.minY + drag.translation.height)))
            NSCursor.closedHand.set()
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
        }
        model.syncFields()
    }
}
