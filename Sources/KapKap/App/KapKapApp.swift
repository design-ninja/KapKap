import SwiftUI

@main
struct KapKapApp: App {
    @State private var store = CaptureStore()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("KapKap", id: "recorder") {
            RecorderView(store: store)
                .windowDismissBehavior(.enabled)
                .onAppear { delegate.store = store }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About KapKap") { AppAbout.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Select Recording Area") {
                    // The panel carries the selection controls now, so it has to be on screen.
                    openWindow(id: "recorder")
                    store.selectArea()
                }
                    .keyboardShortcut("2", modifiers: [.command, .shift]).disabled(store.busy)
            }
        }

        Window("Recordings", id: "recordings") { LibraryView(store: store) }
            .defaultSize(width: 560, height: 380)

        WindowGroup("Editor", id: "editor", for: URL.self) { $url in
            if let url { EditorView(url: url, store: store) }
        }.defaultSize(width: 900, height: 620)

        Settings {
            VStack(spacing: 4) {
                RecordingOptionsView(settings: $store.settings) {
                    CaptureSourceView(store: store)
                    Divider()
                }
                Divider()
                RecordingShortcutView(hotKey: store.recordingHotKey)
            }.padding(20).frame(width: 420)
                .disabled(store.busy)
        }


    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
        configureCloseCommand(in: NSApp.mainMenu)

        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
    }

    private func configureCloseCommand(in menu: NSMenu?) {
        for item in menu?.items ?? [] {
            if item.action == #selector(NSWindow.performClose(_:)) {
                item.target = self
                item.action = #selector(closeWindow(_:))
            }
            configureCloseCommand(in: item.submenu)
        }
    }

    private var windowToClose: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? store?.recorderWindow.flatMap { $0.isVisible ? $0 : nil }
    }

    @objc private func closeWindow(_ sender: Any?) {
        guard let window = windowToClose else { return }
        if EditorCloseCoordinator.intercept(window) { return }
        if window === store?.recorderWindow {
            window.close()
        } else {
            window.performClose(sender)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeWindow(_:)) { return windowToClose != nil }
        return true
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
