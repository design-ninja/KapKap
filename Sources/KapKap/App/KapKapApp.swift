import SwiftUI

@main
struct KapKapApp: App {
    @State private var store = CaptureStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("KapKap", id: "recorder") {
            RecorderView(store: store)
                .onAppear { delegate.store = store }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Select Recording Area") { store.selectArea() }
                    .keyboardShortcut("2", modifiers: [.command, .shift]).disabled(store.busy)
            }
        }

        Window("Recordings", id: "recordings") { LibraryView(store: store) }
            .defaultSize(width: 560, height: 380)

        WindowGroup("Editor", id: "editor", for: URL.self) { $url in
            if let url { EditorView(url: url) }
        }.defaultSize(width: 800, height: 640)

        Settings {
            VStack(spacing: 20) {
                RecordingOptionsView(settings: $store.settings)
                Divider()
                RecordingShortcutView(hotKey: store.recordingHotKey)
            }.padding(24).frame(width: 420)
                .disabled(store.busy)
        }


    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: CaptureStore? {
        didSet { installRecordingShortcut() }
    }
    private var shortcutInstalled = false

    private func installRecordingShortcut() {
        guard !shortcutInstalled, let store else { return }
        shortcutInstalled = true
        let shortcut = store.recordingHotKey
        shortcut.action = { [weak self] in
            guard let store = self?.store else { return }
            Task { @MainActor in
                if store.active {
                    await store.stop()
                    store.recorderWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else if store.phase == .idle {
                    await store.start()
                }
            }
        }
        let status = shortcut.register()
        if status != noErr, let error = shortcut.error { store.error = UserMessage(text: error) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store?.recorderWindow?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.busy else { return .terminateNow }
        store.error = UserMessage(text: "Stop the current recording before quitting KapKap.")
        return .terminateCancel
    }
}
