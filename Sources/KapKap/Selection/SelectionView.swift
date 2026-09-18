import AppKit
import SwiftUI

struct SelectionView: View {
    let cancel: () -> Void
    let completion: (CGRect) -> Void
    @State private var selection = CGRect.zero
    @State private var pointer: CGPoint?
    @State private var dragOrigin: CGRect?
    @State private var moving = false
    @State private var resizeAnchor: CGPoint?
    @State private var ratio = "Free"
    @State private var locked = false
    @State private var width = ""
    @State private var height = ""
    private enum Dimension: Hashable { case width, height }
    @FocusState private var focusedDimension: Dimension?
    private let ratios = ["16:9", "5:4", "5:3", "4:3", "3:2", "1:1", "9:16"]

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
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white))
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
                        syncFields()
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
                if selection.isEmpty {
                    Text("Drag to select · Esc to cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.6), in: Capsule())
                        .position(x: geometry.size.width / 2, y: 50)
                        .allowsHitTesting(false)
                }
                if let pointer {
                    Text(selection.isEmpty ? "\(Int(pointer.x)), \(Int(pointer.y))" : "\(Int(selection.width)) × \(Int(selection.height)) pt")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                        .padding(5).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                        .position(x: min(pointer.x + 55, geometry.size.width - 60), y: min(pointer.y + 18, geometry.size.height - 16))
                        .allowsHitTesting(false)
                }
                SelectionControlsWindow {
                    controls(bounds: geometry.size)
                        .fixedSize()
                        .simultaneousGesture(WindowDragGesture())
                }.frame(width: 0, height: 0)

            }
        }.ignoresSafeArea()
    }

    private func controls(bounds: CGSize) -> some View {
        HStack(spacing: 8) {
            Button(action: cancel) { Image(systemName: "arrow.left") }
                .help("Cancel selection").accessibilityLabel("Cancel selection")
            Picker("Aspect ratio", selection: $ratio) {
                Text("Free").tag("Free")
                ForEach(ratios, id: \.self) { Text($0).tag($0) }
                if ratio == "Custom" { Text("Custom").tag("Custom") }
            }.labelsHidden().frame(width: 90)
                .onChange(of: ratio) { _, value in
                    if value == "Free" { locked = false; return }
                    guard let aspect = aspect(value) else { return }
                    locked = true
                    resize(width: selection.width, height: selection.width / aspect, bounds: bounds)
                }
            Button {
                locked.toggle()
                if locked { ratio = "Custom" }
            } label: { Image(systemName: locked ? "link" : "link.badge.plus") }
                .help(locked ? "Unlock proportions" : "Lock proportions")
                .accessibilityLabel("Lock proportions").accessibilityValue(locked ? "On" : "Off")
            Button {
                if focusedDimension == .height { commitHeight(bounds) }
                else { commitWidth(bounds) }
                focusedDimension = nil
                completion(selection)
            } label: {
                Circle().fill(.red).frame(width: 40, height: 40).frame(width: 62, height: 62)
            }.buttonStyle(.plain).help("Start recording").accessibilityLabel("Start recording")
                .disabled(selection.width < 16 || selection.height < 16)
            TextField("Width", text: $width)
                .focused($focusedDimension, equals: .width)
                .frame(width: 64).onSubmit { commitWidth(bounds) }
                .accessibilityLabel("Selection width in points")
            Button {
                ratio = "Custom"
                resize(width: selection.height, height: selection.width, bounds: bounds)
            } label: { Image(systemName: "arrow.left.arrow.right") }
                .help("Swap width and height").accessibilityLabel("Swap width and height")
            TextField("Height", text: $height)
                .focused($focusedDimension, equals: .height)
                .frame(width: 64).onSubmit { commitHeight(bounds) }
                .accessibilityLabel("Selection height in points")
        }
        .onChange(of: focusedDimension) { previous, _ in
            if previous == .width { commitWidth(bounds) }
            if previous == .height { commitHeight(bounds) }
        }
        .buttonStyle(RecorderIconButtonStyle()).textFieldStyle(.roundedBorder)
        .font(.system(size: 12)).controlSize(.small)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .environment(\.colorScheme, .dark)
        .modifier(RecorderGlass())
        .onHover { inside in
            if inside { pointer = nil; NSCursor.arrow.set() }
        }
    }

    private func aspect(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 ? parts[0] / parts[1] : nil
    }

    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func updateDrag(_ drag: DragGesture.Value, bounds: CGSize) {
        if dragOrigin == nil {
            dragOrigin = selection
            let points = corners(selection)
            if !selection.isEmpty, let index = points.firstIndex(where: { hypot($0.x - drag.startLocation.x, $0.y - drag.startLocation.y) < 12 }) {
                resizeAnchor = points[3 - index]
            }
            moving = resizeAnchor == nil && selection.contains(drag.startLocation)
        }
        guard let original = dragOrigin else { return }
        if moving {
            selection.origin = CGPoint(x: max(0, min(bounds.width - original.width, original.minX + drag.translation.width)),
                                       y: max(0, min(bounds.height - original.height, original.minY + drag.translation.height)))
            NSCursor.closedHand.set()
        } else {
            let start = resizeAnchor ?? drag.startLocation
            let end = CGPoint(x: max(0, min(bounds.width, drag.location.x)), y: max(0, min(bounds.height, drag.location.y)))
            var w = abs(end.x - start.x)
            var h = abs(end.y - start.y)
            if locked, let proportion = aspect(ratio) ?? (original.height > 0 ? original.width / original.height : nil) {
                w = min(w, h * proportion)
                h = w / proportion
            }
            selection = CGRect(x: end.x < start.x ? start.x - w : start.x,
                               y: end.y < start.y ? start.y - h : start.y, width: w, height: h)
            pointer = end
        }
        syncFields()
    }

    private func resize(width: Double, height: Double, bounds: CGSize) {
        guard width.isFinite, height.isFinite, width >= 16, height >= 16 else { syncFields(); return }
        let scale = min(1, bounds.width / width, bounds.height / height)
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        selection = CGRect(x: max(0, min(selection.minX, bounds.width - size.width)),
                           y: max(0, min(selection.minY, bounds.height - size.height)), width: size.width, height: size.height)
        syncFields()
    }

    private func commitWidth(_ bounds: CGSize) {
        guard let value = Double(width) else { syncFields(); return }
        let h = locked && selection.width > 0 ? value * selection.height / selection.width : selection.height
        resize(width: value, height: h, bounds: bounds)
    }

    private func commitHeight(_ bounds: CGSize) {
        guard let value = Double(height) else { syncFields(); return }
        let w = locked && selection.height > 0 ? value * selection.width / selection.height : selection.width
        resize(width: w, height: value, bounds: bounds)
    }

    private func syncFields() {
        width = String(Int(selection.width))
        height = String(Int(selection.height))
    }
}
