import SwiftUI
import UniformTypeIdentifiers

@main
struct KapKapApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var store: CaptureStore { delegate.store }

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(id: "editor", value: url)
    }

    // The recorder is an AppKit panel (RecorderPanel), so every scene here opens only on demand.
    var body: some Scene {
        Window("Recordings", id: "recordings") { LibraryView(store: store) }
            .defaultSize(width: 560, height: 380)
            .defaultLaunchBehavior(.suppressed)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About KapKap") { AppAbout.show() }
                    Button("Check for Updates…") { store.updater.checkForUpdates() }
                        .disabled(!store.updater.canCheckForUpdates)
                }
                CommandGroup(replacing: .newItem) {
                    Button("Select Recording Area") { delegate.selectArea() }
                        .keyboardShortcut(store.selectionHotKey.shortcut.keyboardShortcut).disabled(store.busy)
                    Divider()
                    Button("Open Video…") { openVideo() }.keyboardShortcut("o")
                    Button("Show Recordings Folder") {
                        guard let folder = try? RecordingLibrary.directory() else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
            }

        WindowGroup("Editor", id: "editor", for: URL.self) { $url in
            if let url { EditorView(url: url, store: store) }
        }
        .defaultSize(width: 900, height: 620)
        .defaultLaunchBehavior(.suppressed)

        Settings { SettingsView(store: store) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let store = CaptureStore()
    private var recorder: RecorderPanel?

    /// The panel carries the selection controls, so it has to be on screen first.
    func selectArea() {
        guard store.phase == .idle else { return }
        store.showRecorder()
        store.selectArea()
    }

    private func installRecordingShortcut() {
        let shortcut = store.recordingHotKey
        shortcut.action = { [weak self] in
            guard let store = self?.store else { return }
            Task { @MainActor in
                if store.active {
                    await store.stop()
                    store.showRecorder()
                } else if store.phase == .idle {
                    await store.start()
                }
            }
        }
        let status = shortcut.register()
        if status != noErr, let error = shortcut.error { store.error = UserMessage(text: error) }
        store.selectionHotKey.action = { [weak self] in self?.selectArea() }
        if store.selectionHotKey.register() != noErr, let error = store.selectionHotKey.error {
            store.error = UserMessage(text: error)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureCloseCommand(in: NSApp.mainMenu)
        let recorder = RecorderPanel(store: store)
        self.recorder = recorder
        recorder.orderFrontRegardless()
        installRecordingShortcut()
        ScratchExports.pruneAtLaunch()
        Task { @MainActor in
            let recovered = await RecordingLibrary.recoverPending()
            guard !recovered.isEmpty else { return }
            let store = self.store
            store.refreshLibrary()
            store.error = UserMessage(text: recovered.count == 1
                ? "An unfinished recording from an earlier session was recovered. It is in Recent recordings."
                : "\(recovered.count) unfinished recordings from earlier sessions were recovered. They are in Recent recordings.")
        }

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
        NSApp.keyWindow ?? NSApp.mainWindow ?? store.recorderWindow.flatMap { $0.isVisible ? $0 : nil }
    }

    @objc private func closeWindow(_ sender: Any?) {
        guard let window = windowToClose else { return }
        if EditorCloseCoordinator.intercept(window) { return }
        if window === store.recorderWindow {
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
        store.showRecorder()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting, logging out or shutting down saves a running recording first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.busy else { return .terminateNow }
        Task { @MainActor in
            await store.finishForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
