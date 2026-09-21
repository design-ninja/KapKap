import AppKit
import Observation

/// Selection state lives outside the overlay so the recorder panel can drive it from its own window.
@MainActor @Observable
final class SelectionModel {
    static let ratios = ["16:9", "5:4", "5:3", "4:3", "3:2", "1:1", "9:16"]

    /// View coordinates on `screenFrame`: top-left origin, points.
    var rect = CGRect.zero
    var displayID: CGDirectDisplayID?
    var screenFrame = CGRect.zero
    var bounds = CGSize.zero
    var scale: CGFloat = 2
    var ratio = "Free"
    var locked = false
    var widthText = ""
    var heightText = ""
    /// True while an area is being drawn, so the panel can step out of the way.
    var interacting = false

    var ready: Bool { rect.width >= 16 && rect.height >= 16 }
    var hasArea: Bool { displayID != nil && !rect.isEmpty }

    func reset() {
        rect = .zero
        displayID = nil
        screenFrame = .zero
        bounds = .zero
        ratio = "Free"
        locked = false
        interacting = false
        syncFields()
    }

    /// A drag on another display moves the selection there instead of leaving two of them behind.
    func activate(displayID: CGDirectDisplayID, screenFrame: CGRect, scale: CGFloat, bounds: CGSize) {
        if self.displayID != displayID { rect = .zero }
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.scale = scale
        self.bounds = bounds
    }

    func aspect(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 ? parts[0] / parts[1] : nil
    }

    func resize(width: Double, height: Double) {
        guard bounds.width > 0, bounds.height > 0,
              width.isFinite, height.isFinite, width >= 16, height >= 16 else { syncFields(); return }
        let scale = min(1, bounds.width / width, bounds.height / height)
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        rect = CGRect(x: max(0, min(rect.minX, bounds.width - size.width)),
                      y: max(0, min(rect.minY, bounds.height - size.height)),
                      width: size.width, height: size.height)
        syncFields()
    }

    func commitWidth() {
        guard let value = Double(widthText) else { syncFields(); return }
        resize(width: value, height: locked && rect.width > 0 ? value * rect.height / rect.width : rect.height)
    }

    func commitHeight() {
        guard let value = Double(heightText) else { syncFields(); return }
        resize(width: locked && rect.height > 0 ? value * rect.width / rect.height : rect.width, height: value)
    }

    func applyRatio(_ value: String) {
        if value == "Free" { locked = false; return }
        guard let aspect = aspect(value) else { return }
        locked = true
        resize(width: rect.width, height: rect.width / aspect)
    }

    func swapDimensions() {
        ratio = "Custom"
        resize(width: rect.height, height: rect.width)
    }

    func syncFields() {
        widthText = String(Int(rect.width))
        heightText = String(Int(rect.height))
    }

    func target() -> CaptureTarget? {
        guard let displayID, ready else { return nil }
        let global = CGRect(x: screenFrame.minX + rect.minX, y: screenFrame.maxY - rect.maxY,
                            width: rect.width, height: rect.height)
        return CaptureTarget(displayID: displayID, screenFrame: screenFrame, rect: global,
                             scale: scale, name: "Selected area")
    }
}
