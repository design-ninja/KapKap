import SwiftUI
import AppKit

/// The capture source row, shared by the recorder panel and Settings.
struct CaptureSourceView: View {
    @Bindable var store: CaptureStore

    var body: some View {
        HStack(spacing: 10) {
            Text("Display")
            Spacer(minLength: 12)
            Picker("Display", selection: Binding<UInt32?>(get: {
                guard let target = store.target, target.windowID == nil,
                      target.rect == target.screenFrame else { return nil }
                return target.displayID
            }, set: { displayID in
                guard let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                }) else { return }
                store.selectDisplay(screen)
            })) {
                if store.target == nil || store.target?.windowID != nil || store.hasSelectedArea {
                    Text(store.target?.name ?? "Choose a source").tag(UInt32?.none)
                }
                ForEach(NSScreen.screens, id: \.self) { screen in
                    if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                        Text(screen.localizedName).tag(Optional(id.uint32Value))
                    }
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
            .help(store.target?.name ?? "Display or window").disabled(store.busy)
        }
        .frame(minHeight: 30)
        .font(.system(size: 12))
        .controlSize(.small)
    }
}
