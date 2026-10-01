import AppKit
import Observation
import ScreenCaptureKit

struct UserMessage: Identifiable {
    let id = UUID()
    let text: String
    /// A System Settings pane that fixes the problem, offered next to OK.
    var settingsURL: URL? = nil
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
    /// Shown by the recorder panel, which is often hidden (while recording, or behind an editor),
    /// so a new message brings it forward.
    var error: UserMessage? {
        didSet { if error != nil { revealRecorder() } }
    }
    var recent: [URL] = []
    var latestRecording: URL?
    var windows: [SCWindow] = []
    var isLoadingWindows = false
    var startedAt: Date?
    var pausedAt: Date?
    var pauseDuration: TimeInterval = 0
    var changingPause = false
    @ObservationIgnored weak var recorderWindow: NSWindow?
    @ObservationIgnored private var openEditors = 0
    @ObservationIgnored private var restoreRecorderWindow = false
    let selectionModel = SelectionModel()
    @ObservationIgnored private var outlinedWindow: (id: CGWindowID, processID: pid_t)?
    @ObservationIgnored private var frontAppWatcher: NSObjectProtocol?
    /// Why ScreenCaptureKit ended the current recording on its own, reported once it is saved.
    @ObservationIgnored private var interruption: Error?
    @ObservationIgnored private let defaults: UserDefaults
    private let recorder = ScreenRecorder()
    private let selection = SelectionOverlay()
    private let areaOverlay = RecordingOverlay()

    var hasSelectedArea: Bool { target.map { $0.windowID == nil && $0.rect != $0.screenFrame } ?? false }

    var active: Bool { phase == .recording || phase == .paused }
    var busy: Bool { phase != .idle && phase != .selecting }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recorder.onFailure = { [weak self] error in
            guard let self, self.active else { return }
            self.interruption = error
            Task { await self.stop() }
        }
        if let area = lastArea {
            target = area
        } else if let screen = NSScreen.screens.first(where: { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }) ?? NSScreen.main {
            selectDisplay(screen)
        }
        refreshLibrary()
    }

    private func revealRecorder() { showRecorder() }

    /// The panel takes key without activating KapKap, so it appears over whatever space is in front,
    /// including another app's full screen.
    func showRecorder() {
        recorderWindow?.makeKeyAndOrderFront(nil)
    }

    /// The editor is the focus while it is open; the recorder panel would only float on top of it.
    /// A message waiting on the panel keeps it in front.
    func editorOpened() {
        openEditors += 1
        guard openEditors == 1, error == nil else { return }
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
        // The recorder's permanent overlay level is above the selection canvas.
        if let window = recorderWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func cancelSelection() {
        guard phase == .selecting else { return }
        selection.close()
        phase = .idle
        areaOverlay.close()
        if let screen = recorderWindow?.screen ?? NSScreen.main { selectDisplay(screen) }
        recorderWindow?.makeKeyAndOrderFront(nil)
    }

    func startSelectedArea() {
        guard phase == .selecting, let target = selectionModel.target() else { return }
        // Hide before changing phase, so the main controls never flash while start() is queued.
        recorderWindow?.orderOut(nil)
        selection.close()
        phase = .idle
        self.target = target
        if let identifier = SavedCaptureArea.identifier(for: target.displayID) {
            SavedCaptureArea(displayIdentifier: identifier, selection: target.rect, screen: target.screenFrame).save(defaults: defaults)
        }
        Task { await start() }
    }

    /// The last area drawn, while its display is connected and still holds it.
    var lastArea: CaptureTarget? { SavedCaptureArea.load(defaults: defaults)?.target() }

    func selectLastArea() {
        guard !busy, let area = lastArea else { return }
        clearWindowOutline()
        areaOverlay.close()
        target = area
    }

    func selectDisplay(_ screen: NSScreen) {
        guard !busy, let id = screen.displayID else { return }
        clearWindowOutline()
        areaOverlay.close()
        target = CaptureTarget(displayID: id, screenFrame: screen.frame, rect: screen.frame,
                               scale: screen.backingScaleFactor, name: screen.localizedName)
    }

    /// Returns false when Screen Recording is not allowed; macOS asks for it with its own dialog.
    @discardableResult
    func loadWindows() async -> Bool {
        guard !busy else { return true }
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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
            return true
        } catch {
            windows = []
            if CapturePermissions.isDenied(error) { return false }
            self.error = UserMessage(text: error.localizedDescription)
            return true
        }
    }

    func selectWindow(_ window: SCWindow) {
        guard !busy else { return }
        clearWindowOutline()
        let screen = NSScreen.screens.first { screen in
            screen.displayID.map { CGDisplayBounds($0).intersects(window.frame) } ?? false
        } ?? NSScreen.main
        guard let screen, let displayID = screen.displayID else { return }
        areaOverlay.close()
        // Picking the current window again clears the choice and falls back to the display behind it.
        guard target?.windowID != window.windowID else { return selectDisplay(screen) }
        let target = CaptureTarget(displayID: displayID, screenFrame: screen.frame,
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
              let frame = CaptureWindowGeometry.liveFrame(outlined.id) else {
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

    /// ScreenCaptureKit reports window frames top-left down; AppKit panels are laid out bottom-left up.
    private static func screenRect(_ frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return frame }
        return CaptureWindowGeometry.screenRect(frame, primary: primary.frame)
    }

    func start() async {
        guard phase == .idle, let chosen = target else { return }
        let target: CaptureTarget
        do { target = try Self.current(chosen) } catch {
            self.error = UserMessage(text: error.localizedDescription)
            return
        }
        self.target = target
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
            if settings.microphone { await playStartSound() }
            try await recorder.start(target: target, settings: settings)
            if !settings.microphone { await playStartSound() }
            interruption = nil
            startedAt = Date()
            pausedAt = nil
            pauseDuration = 0
            phase = .recording
            recorderWindow?.orderOut(nil)
        } catch {
            phase = .idle
            areaOverlay.close()
            recorderWindow?.makeKeyAndOrderFront(nil)
            // macOS answers a missing Screen Recording permission with its own dialog.
            guard !CapturePermissions.isDenied(error) else { return }
            self.error = UserMessage(text: "Could not start recording.\n\n\(error.localizedDescription)",
                                     settingsURL: (error as? CaptureError)?.settingsURL)
        }
    }

    /// Display geometry can change after a source was chosen (a new resolution, a rearranged or
    /// disconnected display), so the target is measured again right before recording.
    static func current(_ target: CaptureTarget, screens: [NSScreen] = NSScreen.screens) throws -> CaptureTarget {
        guard target.windowID == nil else { return target }
        guard let screen = screens.first(where: { $0.displayID == target.displayID }) else {
            throw CaptureError.message("The selected display is no longer connected. Select an area again.")
        }
        return try current(target, screenFrame: screen.frame, scale: screen.backingScaleFactor, name: screen.localizedName)
    }

    static func current(_ target: CaptureTarget, screenFrame: CGRect, scale: CGFloat, name: String) throws -> CaptureTarget {
        if target.rect == target.screenFrame {
            return CaptureTarget(displayID: target.displayID, screenFrame: screenFrame, rect: screenFrame,
                                 scale: scale, name: name)
        }
        guard screenFrame.size == target.screenFrame.size else {
            throw CaptureError.message("The display's resolution changed. Select the area again.")
        }
        let rect = target.rect.offsetBy(dx: screenFrame.minX - target.screenFrame.minX,
                                        dy: screenFrame.minY - target.screenFrame.minY)
        return CaptureTarget(displayID: target.displayID, screenFrame: screenFrame, rect: rect,
                             scale: scale, name: target.name)
    }

    /// The start chime never lands in the recording. System audio leaves out KapKap's own sounds, but a
    /// microphone would pick it up from the speakers, so then it plays out before the capture begins.
    private func playStartSound() async {
        guard let sound = NSSound(named: "Pop")?.copy() as? NSSound else { return }
        sound.play()
        guard settings.microphone else { return }
        try? await Task.sleep(for: .seconds(sound.duration + 0.15))
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
        guard active else { return }
        // A pause or resume in flight finishes first; a stop is never dropped.
        while changingPause { try? await Task.sleep(for: .milliseconds(20)) }
        guard active else { return }
        areaOverlay.close()
        phase = .stopping
        let interruption = self.interruption
        self.interruption = nil
        do {
            latestRecording = try await recorder.stop()
            if let interruption {
                error = UserMessage(text: "Recording stopped: \(interruption.localizedDescription)\n\nEverything recorded until then was saved.")
            }
        } catch { self.error = UserMessage(text: "Could not finish recording.\n\n\(error.localizedDescription)") }
        refreshLibrary()
        phase = .idle
        startedAt = nil
    }

    /// Saves a running recording before KapKap quits, logs out or shuts down.
    func finishForTermination() async {
        var waited = 0
        while phase == .starting || phase == .stopping || changingPause, waited < 200 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        if active { await stop() }
    }

    func duration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pauseDuration)
    }
}
