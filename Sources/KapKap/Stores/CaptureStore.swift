import AppKit
import Observation
import ScreenCaptureKit

struct UserMessage: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor @Observable
final class CaptureStore {
    enum Phase { case idle, selecting, starting, recording, paused, stopping }
    var phase = Phase.idle
    var target: CaptureTarget?
    var settings = RecordingSettings()
    let recordingHotKey = RecordingHotKey()
    let selectionHotKey = RecordingHotKey(preferenceKey: "selectionShortcut", id: 2, standard: .selection)
    let updater = Updater()
    var error: UserMessage?
    var recent: [URL] = []
    var latestRecording: URL?
    var windows: [SCWindow] = []
    var isLoadingWindows = false
    var startedAt: Date?
    var pausedAt: Date?
    var pauseDuration: TimeInterval = 0
    var changingPause = false
    var needsScreenAccess = false
    @ObservationIgnored weak var recorderWindow: NSWindow?
    @ObservationIgnored private var openEditors = 0
    @ObservationIgnored private var restoreRecorderWindow = false
    let selectionModel = SelectionModel()
    @ObservationIgnored private var outlinedWindow: (id: CGWindowID, processID: pid_t)?
    @ObservationIgnored private var frontAppWatcher: NSObjectProtocol?
    @ObservationIgnored private var recorderLevel: NSWindow.Level?
    private let recorder = ScreenRecorder()
    private let selection = SelectionOverlay()
    private let areaOverlay = RecordingOverlay()

    var hasSelectedArea: Bool { target.map { $0.windowID == nil && $0.rect != $0.screenFrame } ?? false }

    var active: Bool { phase == .recording || phase == .paused }
    var busy: Bool { phase != .idle && phase != .selecting }

    init() {
        recorder.onFailure = { [weak self] error in
            guard let self else { return }
            self.error = UserMessage(text: error.localizedDescription)
            if self.active { Task { await self.stop() } }
        }
        let builtIn = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }
        if let screen = builtIn ?? NSScreen.main { selectDisplay(screen) }
        refreshLibrary()
    }

    /// The editor is the focus while it is open; the recorder panel would only float on top of it.
    func editorOpened() {
        openEditors += 1
        guard openEditors == 1 else { return }
        restoreRecorderWindow = recorderWindow?.isVisible ?? false
        recorderWindow?.orderOut(nil)
    }

    func editorClosed() {
        openEditors = max(0, openEditors - 1)
        guard openEditors == 0, restoreRecorderWindow else { return }
        restoreRecorderWindow = false
        recorderWindow?.makeKeyAndOrderFront(nil)
    }

    func refreshLibrary() {
        do { recent = try RecordingLibrary.recent() }
        catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    func selectArea() {
        guard phase == .idle else { return }
        clearWindowOutline()
        areaOverlay.close()
        selectionModel.reset()
        phase = .selecting
        selection.present(model: selectionModel) { [weak self] in self?.cancelSelection() }
        // The panel stays put and swaps its controls, so it has to float above the overlay.
        if let window = recorderWindow {
            if recorderLevel == nil { recorderLevel = window.level }
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func cancelSelection() {
        guard phase == .selecting else { return }
        selection.close()
        phase = .idle
        restoreRecorderLevel()
        areaOverlay.close()
        if let screen = recorderWindow?.screen ?? NSScreen.main { selectDisplay(screen) }
        recorderWindow?.makeKeyAndOrderFront(nil)
    }

    func startSelectedArea() {
        guard phase == .selecting, let target = selectionModel.target() else { return }
        selection.close()
        phase = .idle
        restoreRecorderLevel()
        self.target = target
        Task { await start() }
    }

    private func restoreRecorderLevel() {
        guard let window = recorderWindow, let level = recorderLevel else { return }
        window.level = level
        recorderLevel = nil
    }

    func selectDisplay(_ screen: NSScreen) {
        guard !busy, let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        clearWindowOutline()
        areaOverlay.close()
        target = CaptureTarget(displayID: id.uint32Value, screenFrame: screen.frame, rect: screen.frame,
                               scale: screen.backingScaleFactor, name: screen.localizedName)
    }

    func loadWindows() async {
        guard !busy else { return }
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            needsScreenAccess = false
            var seen = Set<String>()
            // Helper panels and background agents are noise here: one entry per app, front to back.
            windows = content.windows.filter { window in
                guard let application = window.owningApplication,
                      application.processID != ProcessInfo.processInfo.processIdentifier,
                      !application.applicationName.isEmpty,
                      window.isOnScreen, window.windowLayer == 0,
                      window.frame.width > 120, window.frame.height > 80 else { return false }
                return seen.insert(application.bundleIdentifier).inserted
            }
        } catch {
            windows = []
            if CapturePermissions.isDenied(error) { needsScreenAccess = true }
            else { self.error = UserMessage(text: error.localizedDescription) }
        }
    }

    func selectWindow(_ window: SCWindow) {
        guard !busy else { return }
        clearWindowOutline()
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayBounds(number.uint32Value).intersects(window.frame)
        } ?? NSScreen.main
        guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        areaOverlay.close()
        // Picking the current window again clears the choice and falls back to the display behind it.
        guard target?.windowID != window.windowID else { return selectDisplay(screen) }
        let target = CaptureTarget(displayID: number.uint32Value, screenFrame: screen.frame,
                                   rect: Self.screenRect(window.frame), scale: screen.backingScaleFactor,
                                   windowID: window.windowID,
                                   name: window.owningApplication?.applicationName ?? window.title ?? "Window")
        self.target = target
        outlinedWindow = window.owningApplication.map { (window.windowID, $0.processID) }
        watchFrontApp()
        // Bring the app forward and outline it, so the chosen window is both visible and obviously framed.
        if let processID = window.owningApplication?.processID {
            NSRunningApplication(processIdentifier: processID)?.activate()
            // That activation raises the app over the recorder, which still has to be reachable.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.recorderWindow?.orderFrontRegardless()
            }
        }
        areaOverlay.show(target: target, recording: false)
    }

    /// The outline is drawn once from the window's frame, so it only makes sense while that window
    /// is in front: it follows the app's activation instead of lingering over whatever replaced it.
    private func watchFrontApp() {
        guard frontAppWatcher == nil else { return }
        frontAppWatcher = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    self?.frontAppChanged(to: application?.processIdentifier)
                }
            }
    }

    private func frontAppChanged(to processID: pid_t?) {
        guard let outlined = outlinedWindow, phase == .idle else { return }
        guard processID == outlined.processID || processID == ProcessInfo.processInfo.processIdentifier else {
            areaOverlay.close()
            return
        }
        refreshWindowOutline()
    }

    /// Redraws from the window's current frame, because it may have moved while it was away.
    private func refreshWindowOutline() {
        guard let outlined = outlinedWindow, let target, target.windowID == outlined.id,
              let frame = Self.liveWindowFrame(outlined.id) else {
            areaOverlay.close()
            return
        }
        let updated = CaptureTarget(displayID: target.displayID, screenFrame: target.screenFrame,
                                    rect: Self.screenRect(frame), scale: target.scale,
                                    windowID: target.windowID, name: target.name)
        self.target = updated
        areaOverlay.show(target: updated, recording: false)
    }

    private func clearWindowOutline() {
        outlinedWindow = nil
        if let frontAppWatcher {
            NSWorkspace.shared.notificationCenter.removeObserver(frontAppWatcher)
            self.frontAppWatcher = nil
        }
    }

    private static func liveWindowFrame(_ id: CGWindowID) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return frame
    }

    /// ScreenCaptureKit reports window frames top-left down; AppKit panels are laid out bottom-left up.
    private static func screenRect(_ frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    func start() async {
        guard phase == .idle else { return }
        guard let target else { return }
        phase = .starting
        settings.save()
        latestRecording = nil
        let recorderWindow = self.recorderWindow
        recorderWindow?.orderOut(nil)
        // KapKap's own windows are excluded from the capture, so there is nothing to wait for:
        // the frame goes up immediately and the stream starts underneath it.
        if target.windowID == nil { areaOverlay.show(target: target, recording: true) }
        else { clearWindowOutline(); areaOverlay.close() }
        do {
            try await recorder.start(target: target, settings: settings)
            needsScreenAccess = false
            startedAt = Date()
            pausedAt = nil
            pauseDuration = 0
            phase = .recording
            recorderWindow?.orderOut(nil)
        } catch {
            phase = .idle
            areaOverlay.close()
            recorderWindow?.makeKeyAndOrderFront(nil)
            if CapturePermissions.isDenied(error) { needsScreenAccess = true }
            else { self.error = UserMessage(text: "Could not start recording.\n\n\(error.localizedDescription)") }
        }
    }

    func togglePause() async {
        guard active, !changingPause else { return }
        changingPause = true
        defer { changingPause = false }
        let pause = phase == .recording
        await recorder.pause(pause)
        if pause { pausedAt = Date() }
        else if let pausedAt { pauseDuration += Date().timeIntervalSince(pausedAt); self.pausedAt = nil }
        phase = pause ? .paused : .recording
    }

    func stop() async {
        guard active, !changingPause else { return }
        areaOverlay.close()
        phase = .stopping
        do {
            latestRecording = try await recorder.stop()
            refreshLibrary()
        } catch { self.error = UserMessage(text: "Could not finish recording.\n\n\(error.localizedDescription)") }
        phase = .idle
        startedAt = nil
    }

    func duration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pauseDuration)
    }
}
