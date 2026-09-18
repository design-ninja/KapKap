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
                fps = max(1, min(60, Int(rate.rounded())))
                let metadata = try await asset.load(.commonMetadata)
                for item in metadata where item.commonKey == .commonKeyDescription {
                    if let text = try await item.load(.stringValue), text.hasPrefix("KapKap recording fps="),
                       let recordedFPS = Int(text.dropFirst("KapKap recording fps=".count)), (1...60).contains(recordedFPS) {
                        fps = recordedFPS
                    }
                }
                sourceFPS = fps
            }
            loaded = true
        } catch { self.error = UserMessage(text: error.localizedDescription) }
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
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("KapKap/Clipboard/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(format.fileExtension)
            export(to: destination, copyToClipboard: true)
        } catch { self.error = UserMessage(text: error.localizedDescription) }
    }

    private func export(to destination: URL, copyToClipboard: Bool) {
        guard !exporting else { return }
        player.pause()
        exporting = true
        exportedURL = nil
        copiedToClipboard = false
        let options = ExportOptions(format: format, start: start, end: end,
                                    width: width, fps: fps, muted: muted, quality: quality)
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
                self.exportedURL = destination
            } catch is CancellationError { }
            catch { self.error = UserMessage(text: error.localizedDescription) }
        }
    }

    func cancelExport() { exportTask?.cancel() }
}
