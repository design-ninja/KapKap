import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case mp4 = "MP4", gif = "GIF", apng = "APNG", webm = "WebM", hevc = "HEVC", av1 = "AV1"
    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .mp4, .hevc, .av1: return "mp4"
        case .gif: return "gif"
        case .apng: return "png"
        case .webm: return "webm"
        }
    }
}

/// How hard video formats compress: a smaller file, or a sharper picture. GIF and APNG ignore it.
public enum ExportQuality: String, CaseIterable, Identifiable, Sendable {
    case smaller, balanced, best
    public var id: String { rawValue }

    /// Constant rate factor per encoder: lower keeps more detail and makes a bigger file.
    func crf(for format: ExportFormat) -> Int {
        let (smaller, balanced, best): (Int, Int, Int)
        switch format {
        case .mp4: (smaller, balanced, best) = (28, 20, 14)
        case .hevc: (smaller, balanced, best) = (30, 22, 16)
        case .webm, .av1: (smaller, balanced, best) = (42, 32, 22)
        case .gif, .apng: return 0
        }
        switch self {
        case .smaller: return smaller
        case .balanced: return balanced
        case .best: return best
        }
    }
}

public struct ExportOptions: Sendable {
    public var format: ExportFormat
    public var start: Double
    public var end: Double
    public var width: Int
    public var fps: Int
    public var muted: Bool
    public var quality: ExportQuality
    /// GIF and APNG only: play forever, or once.
    public var loop: Bool
    /// Audio tracks in the source: a recording with system audio and a microphone has two, and an
    /// export would otherwise keep only the first.
    public var audioTracks: Int

    public init(format: ExportFormat, start: Double, end: Double, width: Int, fps: Int, muted: Bool,
                quality: ExportQuality = .balanced, loop: Bool = true, audioTracks: Int = 1) {
        self.format = format; self.start = start; self.end = end
        self.width = width; self.fps = fps; self.muted = muted; self.quality = quality; self.loop = loop
        self.audioTracks = audioTracks
    }

    public func arguments(input: URL, output: URL) throws -> [String] {
        guard start.isFinite, end.isFinite, start >= 0, end > start, width >= 2, fps > 0, fps <= FrameRate.maximum else {
            throw NSError(domain: "KapKap.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid export range, dimensions or frame rate."])
        }
        let crf = String(quality.crf(for: format))
        let scale = "fps=\(fps),scale=\(width / 2 * 2):-2:flags=lanczos"
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-ss", Self.seconds(start), "-i", input.path,
                    "-t", Self.seconds(end - start)]
        switch format {
        case .gif:
            args += ["-filter_complex", "\(scale),split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a", "-an", "-loop", loop ? "0" : "-1"]
        case .apng:
            args += ["-vf", scale, "-an", "-plays", loop ? "0" : "1", "-f", "apng"]
        case .mp4:
            args += ["-vf", scale, "-c:v", "libx264", "-preset", "fast", "-crf", crf,
                     "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
        case .hevc:
            args += ["-vf", scale, "-c:v", "libx265", "-preset", "medium", "-crf", crf,
                     "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-movflags", "+faststart"]
        case .webm:
            args += ["-vf", scale, "-c:v", "libvpx-vp9", "-crf", crf, "-b:v", "0", "-pix_fmt", "yuv420p"]
        case .av1:
            args += ["-vf", scale, "-c:v", "libsvtav1", "-crf", crf, "-preset", "8", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
        }
        if format != .gif && format != .apng {
            if muted || audioTracks == 0 {
                args += ["-an"]
            } else {
                if audioTracks > 1 {
                    let inputs = (0..<audioTracks).map { "[0:a:\($0)]" }.joined()
                    args += ["-filter_complex", "\(inputs)amix=inputs=\(audioTracks):duration=longest:normalize=0[mix]",
                             "-map", "0:v:0", "-map", "[mix]"]
                }
                args += ["-c:a", format == .webm ? "libopus" : "aac", "-b:a", audioTracks > 1 ? "192k" : "128k"]
            }
        }
        return args + [output.path]
    }

    /// FFmpeg rejects exponent notation, which `String(Double)` produces below 0.0001 (a trim handle
    /// nudged back to the start can land on 2.8e-17).
    static func seconds(_ value: Double) -> String { String(format: "%.6f", value) }
}
