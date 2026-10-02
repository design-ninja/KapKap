import Foundation
import CaptureCore

/// App-wide export choices that Kap keeps in its preferences rather than per export.
enum ExportPreferences {
    private static let directoryKey = "exportDirectory"
    private static let loopKey = "loopExports"
    private static let qualityKey = "exportQuality"
    private static let gifQualityKey = "gifExportQuality"
    private static let hardwareKey = "hardwareEncoding"
    private static let formatKey = "exportFormat"
    private static let frameRateKey = "exportFrameRate"
    private static let copyDestinationKey = "exportToClipboard"

    /// Where the save dialog opens: the Desktop until the user picks another folder.
    static var directory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: directoryKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultDirectory
        }
        set { UserDefaults.standard.set(newValue.path, forKey: directoryKey) }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// The folder, created on first use; a folder that was deleted meanwhile falls back to the default.
    static func preparedDirectory() -> URL {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return directory
        }
        let fallback = directory == defaultDirectory ? directory : defaultDirectory
        try? manager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// GIF and APNG loop forever unless the user turns it off.
    static var loop: Bool {
        get { UserDefaults.standard.object(forKey: loopKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: loopKey) }
    }

    /// The last quality chosen in the editor for GIF, or for video formats, reused for the next export
    /// of that kind: a light GIF and a sharp MP4 are often wanted side by side.
    static func quality(for format: ExportFormat) -> ExportQuality {
        UserDefaults.standard.string(forKey: qualityKey(for: format)).flatMap(ExportQuality.init(rawValue:)) ?? .balanced
    }

    static func setQuality(_ quality: ExportQuality, for format: ExportFormat) {
        UserDefaults.standard.set(quality.rawValue, forKey: qualityKey(for: format))
    }

    private static func qualityKey(for format: ExportFormat) -> String {
        format == .gif ? gifQualityKey : qualityKey
    }

    /// MP4 and HEVC on the Mac's media engine: several times faster, bigger files. Off until chosen.
    static var hardware: Bool {
        get { UserDefaults.standard.bool(forKey: hardwareKey) }
        set { UserDefaults.standard.set(newValue, forKey: hardwareKey) }
    }

    /// The last format chosen in the editor; MP4 until one is picked.
    static var format: ExportFormat {
        get { UserDefaults.standard.string(forKey: formatKey).flatMap(ExportFormat.init(rawValue:)) ?? .mp4 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: formatKey) }
    }

    /// A reduced export rate, or nil for the recording's own rate. Recordings differ in rate, so a
    /// rate the next one cannot reach falls back to its native rate.
    static var frameRate: Int? {
        get { UserDefaults.standard.object(forKey: frameRateKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: frameRateKey) }
    }

    /// Whether the export button copies to the clipboard (the default) or saves to a file.
    static var copyDestination: Bool {
        get { UserDefaults.standard.object(forKey: copyDestinationKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyDestinationKey) }
    }
}
