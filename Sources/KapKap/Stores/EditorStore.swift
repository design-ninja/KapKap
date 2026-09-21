import AppKit
import AVFoundation
import Observation
import CaptureCore
import UniformTypeIdentifiers

@MainActor @Observable
final class EditorStore {
    let url: URL
    let player: AVPlayer
    var duration: Double = 0
    var start: Double = 0
    var end: Double = 1
    var width = 1280
    var sourceWidth = 1280
    var sourceHeight = 720
    var exportHeight: Int { max(2, Int((Double(width) * Double(sourceHeight) / Double(sourceWidth) / 2).rounded()) * 2) }
    var fps = 30
    private var sourceFPS = 30
    private var audioTracks = 1
    var frameRateChoices: [Int] { FrameRate.choices(upTo: sourceFPS) }
    var format = ExportFormat.mp4
    var quality = MP4Quality.balanced
    var keepOriginal = false
    var canKeepOriginal: Bool {
        format == .mp4 && url.pathExtension.lowercased() == "mp4"
            && start == 0 && end == duration && width == sourceWidth && fps == sourceFPS && !muted
    }
    var muted = false
    var exporting = false
    var exportedURL: URL?
    var copiedToClipboard = false
    var error: UserMessage?
    var loaded = false
    var copyDestination = true
    var confirmingDiscard = false
    private var closeApproved = false
    var trimmed: Bool { start > 0 || end < duration }
    /// Only KapKap's own recordings are offered for discarding; an imported video is the user's file.
    private var ownRecording: Bool {
        guard let folder = try? RecordingLibrary.directory() else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
    }
    /// A recording exported in any session is never offered for discarding again: macOS reopens editor
    /// windows after a relaunch, and "not exported yet" would then be wrong about a finished export.
    var needsDiscardConfirmation: Bool {
        loaded && exportedURL == nil && !exporting && ownRecording && !ExportedRecordings.contains(url)
    }
    private var exportTask: Task<Void, Never>?
    private let scopedAccess: Bool

    init(url: URL) {
        self.url = url
        scopedAccess = url.startAccessingSecurityScopedResource()
        self.player = AVPlayer(url: url)
    }

    deinit { if scopedAccess { url.stopAccessingSecurityScopedResource() } }

    func load() async {
        guard !loaded else { return }
        do {
            let asset = AVURLAsset(url: url)
            let time = try await asset.load(.duration)
            guard time.seconds.isFinite, time.seconds > 0 else { throw CaptureError.message("This video has no playable duration.") }
            duration = time.seconds; end = time.seconds
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                sourceWidth = max(2, Int(abs(size.applying(transform).width)))
                sourceHeight = max(2, Int(abs(size.applying(transform).height)))
                width = sourceWidth
                let rate = try await track.load(.nominalFrameRate)
                fps = FrameRate.clamp(Int(rate.rounded()))
                let metadata = try await asset.load(.commonMetadata)
                for item in metadata where item.commonKey == .commonKeyDescription {
                    if let text = try await item.load(.stringValue), text.hasPrefix("KapKap recording fps="),
                       let recordedFPS = Int(text.dropFirst("KapKap recording fps=".count)),
                       (1...FrameRate.maximum).contains(recordedFPS) {
                        fps = recordedFPS
                    }
                }
                sourceFPS = fps
            }
            audioTracks = try await asset.loadTracks(withMediaType: .audio).count
            loaded = true
        } catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    /// Returns true when the close was taken over: the confirmation is on screen and owns the window now.
    func requestClose() -> Bool {
        guard !closeApproved, needsDiscardConfirmation else { return false }
        guard !confirmingDiscard else { return true }
        player.pause()
        confirmingDiscard = true
        return true
    }

    /// The answer has been given, so the next close request goes straight through.
    func approveClose() { closeApproved = true }

    func discardRecording() {
        player.pause()
        cancelExport()
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    func resetTrim() {
        start = 0
        end = duration
        seekPreview(0)
    }

    func setExportWidth(_ value: Int) {
        width = min(sourceWidth, max(2, value / 2 * 2))
    }

    func setExportHeight(_ value: Int) {
        setExportWidth(Int(Double(min(sourceHeight, max(2, value))) * Double(sourceWidth) / Double(sourceHeight)))
    }

    func seekPreview(_ time: Double) {
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = .invalid
        player.seek(to: CMTime(seconds: time, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        if player.rate > 0 { player.pause(); return }
        let current = player.currentTime().seconds
        if !current.isFinite || current < start || current >= end - 0.01 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 60_000)
        player.isMuted = muted
        player.play()
    }

    func chooseExport() {
        guard !exporting, loaded else { return }
        player.pause()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        panel.canCreateDirectories = true
        panel.directoryURL = ExportPreferences.preparedDirectory()
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            guard destination.standardizedFileURL != self.url.standardizedFileURL else {
                self.error = UserMessage(text: "Choose a different filename to preserve your original recording.")
                return
            }
            self.export(to: destination, copyToClipboard: false)
        }
    }

    func copyToClipboard() {
        guard !exporting, loaded else { return }
        do { export(to: try scratchDestination(in: "Clipboard"), copyToClipboard: true) }
        catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    /// Apps that can open the current format: the system default first, then by name, one entry per app
    /// even when several copies of it are installed (an old download, an Xcode build).
    var openWithApplications: [URL] {
        guard let type = UTType(filenameExtension: format.fileExtension) else { return [] }
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: type)
        var byIdentifier: [String: URL] = [:]
        for application in workspace.urlsForApplications(toOpen: type) {
            let identifier = Bundle(url: application)?.bundleIdentifier ?? application.path
            if let kept = byIdentifier[identifier], Self.rank(kept, preferred: preferred) <= Self.rank(application, preferred: preferred) { continue }
            byIdentifier[identifier] = application
        }
        return byIdentifier.values.sorted {
            let (left, right) = (Self.rank($0, preferred: preferred), Self.rank($1, preferred: preferred))
            if (left == 0) != (right == 0) { return left == 0 }
            return FileManager.default.displayName(atPath: $0.path)
                .localizedStandardCompare(FileManager.default.displayName(atPath: $1.path)) == .orderedAscending
        }
    }

    /// Which copy of an app to show: the default handler, then the installed one, then anything else.
    private static func rank(_ application: URL, preferred: URL?) -> Int {
        if application.standardizedFileURL == preferred?.standardizedFileURL { return 0 }
        let path = application.path
        return path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/") ? 1 : 2
    }

    /// Kap's "Open With": export to a scratch file and hand it straight to another app.
    func exportAndOpen(with application: URL) {
        guard !exporting, loaded else { return }
        do { export(to: try scratchDestination(in: "Open With"), copyToClipboard: false, openWith: application) }
        catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    private func scratchDestination(in folder: String) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("KapKap/\(folder)/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(format.fileExtension)
    }

    private func export(to destination: URL, copyToClipboard: Bool, openWith application: URL? = nil) {
        guard !exporting else { return }
        player.pause()
        exporting = true
        exportedURL = nil
        copiedToClipboard = false
        let options = ExportOptions(format: format, start: start, end: end,
                                    width: width, fps: fps, muted: muted, quality: quality,
                                    loop: ExportPreferences.loop, audioTracks: audioTracks)
        let preserveOriginal = keepOriginal && canKeepOriginal
        exportTask = Task {
            defer { self.exporting = false; self.exportTask = nil }
            do {
                try await ExportService.export(input: self.url, destination: destination, options: options, preserveOriginal: preserveOriginal)
                if copyToClipboard {
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.writeObjects([destination as NSURL]) else {
                        throw CaptureError.message("Could not copy the exported file to the clipboard.")
                    }
                    self.copiedToClipboard = true
                }
                if let application {
                    _ = try await NSWorkspace.shared.open([destination], withApplicationAt: application,
                                                          configuration: NSWorkspace.OpenConfiguration())
                }
                self.exportedURL = destination
                ExportedRecordings.insert(self.url)
                NSSound(named: "Glass")?.play()
            } catch is CancellationError { }
            catch { self.error = UserMessage(text: error.localizedDescription) }
        }
    }

    func cancelExport() { exportTask?.cancel() }
}

/// Recordings that have been exported at least once, remembered across launches by file name.
enum ExportedRecordings {
    private static let key = "exportedRecordings"

    static func contains(_ url: URL) -> Bool {
        UserDefaults.standard.stringArray(forKey: key)?.contains(url.lastPathComponent) ?? false
    }

    static func insert(_ url: URL) {
        var names = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard names.insert(url.lastPathComponent).inserted else { return }
        UserDefaults.standard.set(names.sorted(), forKey: key)
    }
}
