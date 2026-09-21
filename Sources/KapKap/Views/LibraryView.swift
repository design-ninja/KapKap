import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var store: CaptureStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if store.recent.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "record.circle",
                                       description: Text("Your recordings are saved here automatically."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.recent, id: \.self) { url in
                            RecordingRow(url: url, open: { openWindow(id: "editor", value: url) })
                            if url != store.recent.last {
                                Divider().padding(.leading, 140).padding(.trailing, 20)
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { store.refreshLibrary() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLibrary()
        }
    }
}

private struct RecordingRow: View {
    let url: URL
    let open: () -> Void
    @State private var preview: RecordingPreview?
    @State private var hovered = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color.black
                if let image = preview?.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if hovered {
                RowAction(symbol: "folder", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                RowAction(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy to clipboard", action: copy)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovered ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovered = $0 }
        .help(url.lastPathComponent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording \(title), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        // The tap gesture is invisible to VoiceOver; without this the "button" does nothing when pressed.
        .accessibilityAction { open() }
        .contextMenu {
            Button("Open in Editor") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy") { copy() }
            Divider()
            ShareLink(item: url)
        }
        .task(id: url) { preview = await RecordingPreview.load(url) }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
    }

    private var title: String {
        guard let created = preview?.created else { return url.deletingPathExtension().lastPathComponent }
        return created.formatted(date: .abbreviated, time: .shortened)
    }

    private var subtitle: String {
        guard let preview else { return url.deletingPathExtension().lastPathComponent }
        var parts = [EditorTimelineView.timestamp(preview.duration, precise: false)]
        if preview.pixelSize.width > 0 {
            parts.append("\(Int(preview.pixelSize.width)) × \(Int(preview.pixelSize.height))")
        }
        if preview.size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: preview.size, countStyle: .file))
        }
        return parts.joined(separator: "  ·  ")
    }
}

private struct RowAction: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(hovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .help(help).accessibilityLabel(help)
    }
}

/// Poster frames are expensive enough to keep, and the library redraws them on every scroll.
final class RecordingPreview: @unchecked Sendable {
    let image: NSImage?
    let duration: Double
    let created: Date?
    let size: Int64
    let pixelSize: CGSize

    private init(image: NSImage?, duration: Double, created: Date?, size: Int64, pixelSize: CGSize) {
        self.image = image
        self.duration = duration
        self.created = created
        self.size = size
        self.pixelSize = pixelSize
    }

    nonisolated(unsafe) private static let cache = NSCache<NSURL, RecordingPreview>()

    static func load(_ url: URL) async -> RecordingPreview {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        var pixelSize = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let oriented = size.applying(transform)
            pixelSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        }
        var image: NSImage?
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        if duration > 0, let frame = try? await generator.image(at: CMTime(seconds: duration * 0.1, preferredTimescale: 600)) {
            image = NSImage(cgImage: frame.image, size: .zero)
        }
        let preview = RecordingPreview(image: image, duration: duration.isFinite ? duration : 0,
                                       created: values?.creationDate, size: Int64(values?.fileSize ?? 0),
                                       pixelSize: pixelSize)
        cache.setObject(preview, forKey: url as NSURL)
        return preview
    }
}
