import AVFoundation

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
        // Fixed digits and calendar: the names sort chronologically whatever the user's locale.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return try directory().appendingPathComponent("KapKap \(formatter.string(from: Date())) \(UUID().uuidString.prefix(4)).mp4")
    }

    static func recent() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.creationDateKey],
                                                    options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Unfinished recordings keep a leading dot until they are finalized.
    static func pendingName(for url: URL) -> String { ".\(url.lastPathComponent)" }

    /// Moves a pending file into the library when it plays: recordings are written in fragments, so a
    /// crash or a failed finalization still leaves everything up to the last fragment readable.
    static func recover(_ pending: URL, as destination: URL) async -> Bool {
        let asset = AVURLAsset(url: pending)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              !FileManager.default.fileExists(atPath: destination.path) else { return false }
        return (try? FileManager.default.moveItem(at: pending, to: destination)) != nil
    }

    /// Recovers recordings left behind by a crash. Files still being written are skipped by their age,
    /// and files that cannot play stay hidden for diagnosis.
    @discardableResult
    static func recoverPending(in folder: URL? = nil, olderThan age: TimeInterval = 15) async -> [URL] {
        guard let folder = folder ?? (try? directory()),
              let files = try? FileManager.default.contentsOfDirectory(at: folder,
                  includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var recovered: [URL] = []
        for file in files where file.lastPathComponent.hasPrefix(".KapKap ") && file.pathExtension == "mp4" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > age else { continue }
            let destination = folder.appendingPathComponent(String(file.lastPathComponent.dropFirst()))
            if await recover(file, as: destination) { recovered.append(destination) }
        }
        return recovered
    }
}
