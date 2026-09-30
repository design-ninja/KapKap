import SwiftUI
import AppKit

/// Displays to record, the last area drawn, and the current window when one is chosen. Shared with Settings.
struct DisplayPicker: View {
    @Bindable var store: CaptureStore

    private enum Source: Hashable { case current, lastArea, display(CGDirectDisplayID) }

    var body: some View {
        let lastArea = store.lastArea
        let onLastArea = lastArea.map { store.target?.windowID == nil && store.target?.rect == $0.rect } ?? false
        Picker("Display", selection: Binding<Source>(get: {
            guard let target = store.target, target.windowID == nil else { return .current }
            if target.rect == target.screenFrame { return .display(target.displayID) }
            return onLastArea ? .lastArea : .current
        }, set: { source in
            switch source {
            case .current: break
            case .lastArea: store.selectLastArea()
            case .display(let displayID):
                guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return }
                store.selectDisplay(screen)
            }
        })) {
            if store.target == nil || store.target?.windowID != nil || (store.hasSelectedArea && !onLastArea) {
                Text(store.target?.name ?? "Choose a source").tag(Source.current)
            }
            if lastArea != nil { Text("Last area").tag(Source.lastArea) }
            ForEach(NSScreen.screens, id: \.self) { screen in
                if let displayID = screen.displayID { Text(screen.localizedName).tag(Source.display(displayID)) }
            }
        }
        .pickerStyle(.menu)
        .help(store.target?.name ?? "Display or window").disabled(store.busy)
    }
}
