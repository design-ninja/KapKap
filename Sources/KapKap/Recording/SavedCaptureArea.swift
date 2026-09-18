import AppKit
import CaptureCore

struct SavedCaptureArea: Codable {
    let displayIdentifier: String
    let localRect: CGRect
    private static let preferenceKey = "lastCaptureArea"

    init(displayIdentifier: String, selection: CGRect, screen: CGRect) {
        self.displayIdentifier = displayIdentifier
        localRect = CaptureGeometry.sourceRect(selection: selection, screen: screen)
    }

    func rect(on displayIdentifier: String, screen: CGRect) -> CGRect? {
        guard self.displayIdentifier == displayIdentifier,
              localRect.width >= 2, localRect.height >= 2,
              CGRect(origin: .zero, size: screen.size).contains(localRect) else { return nil }
        return CGRect(x: screen.minX + localRect.minX, y: screen.maxY - localRect.maxY,
                      width: localRect.width, height: localRect.height)
    }

    @MainActor func target() -> CaptureTarget? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let identifier = Self.identifier(for: number.uint32Value),
                  let rect = rect(on: identifier, screen: screen.frame) else { continue }
            return CaptureTarget(displayID: number.uint32Value, screenFrame: screen.frame,
                                 rect: rect, scale: screen.backingScaleFactor, name: "Selected area")
        }
        return nil
    }

    static func identifier(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.preferenceKey)
    }

    static func load(defaults: UserDefaults = .standard) -> Self? {
        defaults.data(forKey: preferenceKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}
