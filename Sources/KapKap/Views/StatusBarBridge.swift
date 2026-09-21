import SwiftUI
import AppKit

struct StatusBarBridge: NSViewRepresentable {
    let store: CaptureStore
    let phase: CaptureStore.Phase
    let showRecorder: () -> Void
    let showLibrary: () -> Void
    let showSettings: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopAnimation()
        NSStatusBar.system.removeStatusItem(coordinator.item)
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        private var configuration: StatusBarBridge
        private var clock: Timer?

        init(_ configuration: StatusBarBridge) {
            self.configuration = configuration
            super.init()
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            update(configuration)
        }

        func update(_ configuration: StatusBarBridge) {
            self.configuration = configuration
            let store = configuration.store
            let symbol = store.active ? (store.phase == .paused ? "pause.circle" : "stop.circle.fill") : "record.circle"
            // The default symbol size reads small against the rest of the menu bar.
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KapKap")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular))
            image?.isTemplate = true
            item.button?.image = image
            // While recording, the elapsed time sits next to the icon; it holds still while paused.
            if store.active {
                if clock == nil {
                    clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.showElapsedTime() }
                    }
                }
                showElapsedTime()
            } else { stopAnimation() }
            switch store.phase {
            case .paused:
                item.button?.toolTip = "Resume recording · Right-click for menu"
            case .recording:
                item.button?.toolTip = "Stop recording · Option-click to pause · Right-click for menu"
            default:
                item.button?.toolTip = "Show KapKap · Right-click for menu"
            }
        }

        func stopAnimation() {
            clock?.invalidate()
            clock = nil
            item.button?.attributedTitle = NSAttributedString()
            item.button?.imagePosition = .imageOnly
        }

        private func showElapsedTime() {
            let seconds = Int(configuration.store.duration(at: Date()))
            let text = String(format: " %02d:%02d", seconds / 60, seconds % 60)
            item.button?.imagePosition = .imageLeading
            item.button?.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ])
            item.button?.setAccessibilityValue("Recording, \(seconds / 60) minutes \(seconds % 60) seconds")
        }

        @objc private func clicked() {
            if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                showMenu()
            } else {
                let store = configuration.store
                guard !store.changingPause else { return }
                switch store.phase {
                case .idle:
                    configuration.showRecorder()
                case .paused:
                    Task { await store.togglePause() }
                case .recording:
                    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                        Task { await store.togglePause() }
                    } else { toggleRecording() }
                default:
                    break
                }
            }
        }

        private func toggleRecording() {
            let store = configuration.store
            guard !store.changingPause else { return }
            Task { @MainActor in
                if store.active {
                    await store.stop()
                    configuration.showRecorder()
                } else if store.phase == .idle {
                    await store.start()
                    if !store.active { configuration.showRecorder() }
                }
            }
        }

        private func showMenu() {
            let store = configuration.store
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            func add(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
                let entry = ActionItem(title: title, action: action)
                entry.isEnabled = enabled
                menu.addItem(entry)
            }
            add("Show KapKap", action: configuration.showRecorder)
            add(store.active ? "Stop Recording (\(store.recordingHotKey.shortcut.label))" : "Start Recording (\(store.recordingHotKey.shortcut.label))",
                enabled: !store.changingPause && (store.active || (store.phase == .idle && store.target != nil))) { [weak self] in
                self?.toggleRecording()
            }
            if store.active {
                add(store.phase == .paused ? "Resume Recording" : "Pause Recording", enabled: !store.changingPause) {
                    Task { await store.togglePause() }
                }
            } else {
                add("Select Area…", enabled: !store.busy) { store.selectArea() }
            }
            menu.addItem(.separator())
            add("Recent Recordings", action: configuration.showLibrary)
            add("Settings…", enabled: !store.busy, action: configuration.showSettings)
            menu.addItem(.separator())
            add("Quit KapKap", enabled: !store.busy) { NSApp.terminate(nil) }
            item.menu = menu
            item.button?.performClick(nil)
        }

        func menuDidClose(_ menu: NSMenu) { item.menu = nil }
    }
}

@MainActor private final class ActionItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, action: @escaping () -> Void) {
        callback = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("Not supported") }
    @objc private func invoke() { callback() }
}
