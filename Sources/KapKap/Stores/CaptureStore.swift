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

    func refreshLibrary() {
        do { recent = try RecordingLibrary.recent() }
        catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    func selectArea() {
        guard !busy else { return }
        areaOverlay.close()
        phase = .selecting
        let recorderWindow = self.recorderWindow
        recorderWindow?.orderOut(nil)
        selection.present { [weak self] target in
            guard let self else { return }
            self.phase = .idle
            if let target {
                self.target = target
                Task { await self.start() }
            } else {
                self.areaOverlay.close()
                if let screen = recorderWindow?.screen ?? NSScreen.main { self.selectDisplay(screen) }
                recorderWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func selectDisplay(_ screen: NSScreen) {
        guard !busy, let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        areaOverlay.close()
        target = CaptureTarget(displayID: id.uint32Value, screenFrame: screen.frame, rect: screen.frame,
                               scale: screen.backingScaleFactor, name: screen.localizedName)
    }

    func loadWindows() async {
        guard !busy else { return }
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            needsScreenAccess = false
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
                $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
            }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
        } catch {
            windows = []
            if CapturePermissions.isDenied(error) { needsScreenAccess = true }
            else { self.error = UserMessage(text: error.localizedDescription) }
        }
    }

    func selectWindow(_ window: SCWindow) {
        guard !busy else { return }
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayBounds(number.uint32Value).intersects(window.frame)
        } ?? NSScreen.main
        guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        areaOverlay.close()
        target = CaptureTarget(displayID: number.uint32Value, screenFrame: screen.frame, rect: window.frame,
                               scale: screen.backingScaleFactor, windowID: window.windowID,
                               name: window.title ?? window.owningApplication?.applicationName ?? "Window")
    }

    func start() async {
        guard phase == .idle else { return }
        guard let target else { return }
        phase = .starting
        settings.save()
        latestRecording = nil
        let recorderWindow = self.recorderWindow
        recorderWindow?.orderOut(nil)
        do {
            try await Task.sleep(for: .milliseconds(500))
            try await recorder.start(target: target, settings: settings)
            needsScreenAccess = false
            startedAt = Date()
            pausedAt = nil
            pauseDuration = 0
            areaOverlay.show(target: target, recording: true)
            phase = .recording
            recorderWindow?.orderOut(nil)
        } catch {
            phase = .idle
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
