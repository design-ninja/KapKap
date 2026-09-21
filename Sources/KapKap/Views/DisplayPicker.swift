import SwiftUI
import AppKit

/// Displays to record, plus the current area or window when one is chosen. Shared with Settings.
struct DisplayPicker: View {
    @Bindable var store: CaptureStore

    var body: some View {
        Picker("Display", selection: Binding<UInt32?>(get: {
            guard let target = store.target, target.windowID == nil,
                  target.rect == target.screenFrame else { return nil }
            return target.displayID
        }, set: { displayID in
            guard let screen = NSScreen.screens.first(where: { Self.id(of: $0) == displayID }) else { return }
            store.selectDisplay(screen)
        })) {
            if store.target == nil || store.target?.windowID != nil || store.hasSelectedArea {
                Text(store.target?.name ?? "Choose a source").tag(UInt32?.none)
            }
            ForEach(NSScreen.screens, id: \.self) { screen in
                if let id = Self.id(of: screen) { Text(screen.localizedName).tag(Optional(id)) }
            }
        }
        .pickerStyle(.menu)
        .help(store.target?.name ?? "Display or window").disabled(store.busy)
    }

    private static func id(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
