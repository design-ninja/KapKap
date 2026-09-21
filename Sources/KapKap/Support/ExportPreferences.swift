import Foundation

/// App-wide export choices that Kap keeps in its preferences rather than per export.
enum ExportPreferences {
    private static let directoryKey = "exportDirectory"
    private static let loopKey = "loopExports"

    /// Where the save dialog opens: `~/Movies/KapKap` until the user picks another folder, like Kap's Kaptures.
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
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/KapKap", isDirectory: true)
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
}
