import Foundation

/// How much data a recording may use. Every export is encoded from the recording, so this also caps
/// the detail an export can keep: games and video need more than a still interface.
public enum RecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard, high
    public var id: String { rawValue }

    /// Average H.264 bit rate: 0.2 bits per pixel per frame, or twice that for High. The ceilings
    /// leave 4K at 60 fps its full rate and stay within what the Mac's encoder sustains.
    public func bitRate(width: Int, height: Int, fps: Int) -> Int {
        let standard = width * height * fps / 5
        switch self {
        case .standard: return min(100_000_000, max(2_000_000, standard))
        case .high: return min(200_000_000, max(4_000_000, standard * 2))
        }
    }
}
