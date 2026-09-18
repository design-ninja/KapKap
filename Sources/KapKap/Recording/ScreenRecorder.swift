import AppKit
import AVFoundation
import ScreenCaptureKit
import CaptureCore

struct CaptureTarget {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let rect: CGRect
    let scale: CGFloat
    var windowID: CGWindowID?
    var name: String
}

@MainActor
final class ScreenRecorder {
    private var stream: SCStream?
    private var sink: SampleWriter?
    private var destination: URL?
    private var temporary: URL?
    var onFailure: ((Error) -> Void)?

    func start(target: CaptureTarget, settings: RecordingSettings) async throws {
        guard stream == nil else { throw CaptureError.message("A recording is already running.") }
        if settings.microphone {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw CaptureError.message("Allow microphone access for KapKap in System Settings → Privacy & Security → Microphone.") }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
            throw CaptureError.message("The selected display is no longer connected. Select an area again.")
        }
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        let source: CGRect
        if let windowID = target.windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.message("The selected window is no longer available.")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            source = CaptureGeometry.pixelAlignedRect(CGRect(origin: .zero, size: window.frame.size),
                                                       scale: CGFloat(filter.pointPixelScale))
            config.ignoreShadowsSingleWindow = true
        } else {
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            source = CaptureGeometry.pixelAlignedRect(
                CaptureGeometry.sourceRect(selection: target.rect, screen: target.screenFrame),
                scale: CGFloat(filter.pointPixelScale))
        }
        guard !source.isEmpty else { throw CaptureError.message("Select a larger area.") }
        config.sourceRect = source
        let size = CaptureGeometry.pixelSize(points: source.size, scale: CGFloat(filter.pointPixelScale))
        config.captureResolution = .best
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        config.queueDepth = 6
        config.showsCursor = settings.showCursor
        config.showMouseClicks = settings.highlightClicks
        config.captureMicrophone = settings.microphone
        config.microphoneCaptureDeviceID = settings.microphoneID
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        let output = try RecordingLibrary.newURL()
        let pending = output.deletingLastPathComponent().appendingPathComponent(".\(output.lastPathComponent)")
        let sink = try SampleWriter(url: pending, width: Int(size.width), height: Int(size.height), settings: settings) { [weak self] error in
            Task { @MainActor in self?.onFailure?(error) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        if settings.microphone { try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue) }
        self.sink = sink
        self.stream = stream
        destination = output
        temporary = pending
        do { try await stream.startCapture() }
        catch { sink.cancel(); self.stream = nil; self.sink = nil; throw error }
    }

    func pause(_ paused: Bool) async { await sink?.setPaused(paused) }

    func stop() async throws -> URL {
        guard let stream, let sink, let destination, let temporary else { throw CaptureError.message("There is no active recording.") }
        defer { self.stream = nil; self.sink = nil; self.destination = nil; self.temporary = nil }
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        var stopError: Error?
        do { try await stream.stopCapture() } catch { stopError = error }
        try await sink.finish(at: stopTime)
        try FileManager.default.moveItem(at: temporary, to: destination)
        if let stopError { NSLog("Capture ended with an error; recording was saved: %@", stopError.localizedDescription) }
        return destination
    }
}
