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

public enum MP4Quality: String, CaseIterable, Identifiable, Sendable {
    case balanced = "Balanced"
    case high = "High quality"
    public var id: String { rawValue }
}

public struct ExportOptions: Sendable {
    public var format: ExportFormat
    public var start: Double
    public var end: Double
    public var width: Int
    public var fps: Int
    public var muted: Bool
    public var quality: MP4Quality

    public init(format: ExportFormat, start: Double, end: Double, width: Int, fps: Int, muted: Bool, quality: MP4Quality = .balanced) {
        self.format = format; self.start = start; self.end = end
        self.width = width; self.fps = fps; self.muted = muted; self.quality = quality
    }

    public func arguments(input: URL, output: URL) throws -> [String] {
        guard start.isFinite, end.isFinite, start >= 0, end > start, width >= 2, fps > 0, fps <= 60 else {
            throw NSError(domain: "KapKap.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid export range, dimensions or frame rate."])
        }
        let scale = "fps=\(fps),scale=\(width / 2 * 2):-2:flags=lanczos"
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-ss", String(start), "-i", input.path,
                    "-t", String(end - start)]
        switch format {
        case .gif:
            args += ["-filter_complex", "\(scale),split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a", "-an", "-loop", "0"]
        case .apng:
            args += ["-vf", scale, "-an", "-plays", "0", "-f", "apng"]
        case .mp4:
            args += ["-vf", scale, "-c:v", "libx264",
                     "-preset", quality == .balanced ? "fast" : "medium",
                     "-crf", quality == .balanced ? "16" : "14",
                     "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
        case .hevc:
            args += ["-vf", scale, "-c:v", "libx265", "-preset", "medium", "-crf", "16",
                     "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-movflags", "+faststart"]
        case .webm:
            args += ["-vf", scale, "-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-pix_fmt", "yuv420p"]
        case .av1:
            args += ["-vf", scale, "-c:v", "libsvtav1", "-crf", "30", "-preset", "8", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
        }
        if format != .gif && format != .apng {
            args += muted ? ["-an"] : ["-c:a", format == .webm ? "libopus" : "aac", "-b:a", "128k"]
        }
        return args + [output.path]
    }
}
