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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        private var configuration: StatusBarBridge
        private var pulseTimer: Timer?
        private var pulseDimmed = false

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
            if store.phase == .recording && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if pulseTimer == nil {
                    pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.pulseDimmed.toggle()
                            NSAnimationContext.runAnimationGroup { context in
                                context.duration = 0.6
                                self.item.button?.animator().alphaValue = self.pulseDimmed ? 0.4 : 1
                            }
                        }
                    }
                }
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
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulseDimmed = false
            item.button?.alphaValue = 1
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
