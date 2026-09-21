import AppKit
import CaptureCore
import SwiftUI

struct RecorderWindowDrag: ViewModifier {
    let store: CaptureStore
    @State private var initialOrigin: CGPoint?
    @State private var initialPointer: CGPoint?
    @State private var snapping = WindowSnapping()

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    guard let window = store.recorderWindow else { return }
                    let pointer = NSEvent.mouseLocation
                    if initialOrigin == nil {
                        initialOrigin = window.frame.origin
                        initialPointer = CGPoint(x: pointer.x - value.translation.width,
                                                 y: pointer.y + value.translation.height)
                        snapping.reset()
                    }
                    guard let initialOrigin, let initialPointer,
                          let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? window.screen else { return }
                    let proposed = CGPoint(x: initialOrigin.x + pointer.x - initialPointer.x,
                                           y: initialOrigin.y + pointer.y - initialPointer.y)
                    let visible = screen.visibleFrame
                    let bounded = CGPoint(
                        x: min(max(proposed.x, visible.minX), max(visible.minX, visible.maxX - window.frame.width)),
                        y: min(max(proposed.y, visible.minY), max(visible.minY, visible.maxY - window.frame.height)))
                    window.setFrameOrigin(snapping.origin(for: bounded, size: window.frame.size,
                                                          visibleFrame: visible))
                }
                .onEnded { _ in
                    if initialOrigin != nil, let window = store.recorderWindow {
                        RecorderWindowPosition.save(window.frame.origin)
                    }
                    initialOrigin = nil
                    initialPointer = nil
                    snapping.reset()
                }
        )
    }
}
