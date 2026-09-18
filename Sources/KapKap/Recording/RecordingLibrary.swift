import Foundation

enum RecordingLibrary {
    static func directory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("KapKap/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func newURL() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return try directory().appendingPathComponent("KapKap \(formatter.string(from: Date())) \(UUID().uuidString.prefix(4)).mp4")
    }

    static func recent() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.creationDateKey],
                                                    options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
