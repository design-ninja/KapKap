import SwiftUI
import AppKit

struct NativeSwitch: NSViewRepresentable {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .regular
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSwitch, context: Context) {
        context.coordinator.parent = self
        control.state = isOn ? .on : .off
        control.isEnabled = isEnabled
        control.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: NativeSwitch
        init(_ parent: NativeSwitch) { self.parent = parent }
        @objc func changed(_ control: NSSwitch) { parent.isOn = control.state == .on }
    }
}
