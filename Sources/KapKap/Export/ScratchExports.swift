import AppKit

/// Exports made for the clipboard or for another app. The pasteboard and the receiving app hold only
/// a file URL, so each export keeps its own folder until nothing can still need it.
enum ScratchExports {
    static let clipboard = "Clipboard"
    static let openWith = "Open With"

    static func folder(_ name: String, root: URL? = nil) throws -> URL {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            .appendingPathComponent("KapKap", isDirectory: true)
        return base.appendingPathComponent(name, isDirectory: true)
    }

    static func newDestination(in name: String, fileName: String, root: URL? = nil) throws -> URL {
        let directory = try folder(name, root: root).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    /// Removes the export folders in `name` that are older than `age`, except the one holding `keeping`.
    static func prune(_ name: String, keeping: URL? = nil, olderThan age: TimeInterval = 0, root: URL? = nil) {
        guard let folder = try? folder(name, root: root),
              let entries = try? FileManager.default.contentsOfDirectory(at: folder,
                  includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { return }
        let kept = keeping.map { $0.deletingLastPathComponent().standardizedFileURL.path }
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true, entry.standardizedFileURL.path != kept else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) >= age { try? FileManager.default.removeItem(at: entry) }
        }
    }

    /// A day is long enough for any paste or app launch; the export still on the pasteboard is kept.
    @MainActor static func pruneAtLaunch() {
        prune(clipboard, keeping: pasteboardFile, olderThan: 24 * 60 * 60)
        prune(openWith, olderThan: 24 * 60 * 60)
    }

    @MainActor private static var pasteboardFile: URL? {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
}
