import SwiftUI
import AVFoundation

struct EditorTimelineView: View {
    @Bindable var model: EditorStore
    let playhead: Double
    @State private var dragStart: Double?
    @State private var dragEnd: Double?
    @State private var hoverTime: Double?

    private var total: Double { max(0.01, model.duration) }
    private var gap: Double { min(0.01, total) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            let left = model.start / total * width + 8
            let right = model.end / total * width + 8
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 4)
                    .padding(.horizontal, 8)
                Capsule().fill(Color.accentColor).frame(width: max(1, right - left), height: 4).offset(x: left)
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        model.seekPreview(min(model.end, max(model.start, (value.location.x - 8) / width * total)))
                    })
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(Self.timestamp(playhead))
                    .accessibilityAdjustableAction { direction in
                        model.seekPreview(min(model.end, max(model.start, playhead + (direction == .increment ? 0.1 : -0.1))))
                    }
                Circle().fill(.white).frame(width: 7, height: 7)
                    .offset(x: min(width, max(0, playhead / total * width)) + 4.5).allowsHitTesting(false)
                handle("Trim start", time: model.start).offset(x: left - 8)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if dragStart == nil { dragStart = model.start }
                        model.start = min(model.end - gap, max(0, (dragStart ?? model.start) + value.translation.width / width * total))
                        model.seekPreview(model.start); hoverTime = model.start
                    }.onEnded { _ in dragStart = nil; hoverTime = nil })
                    .accessibilityAdjustableAction { direction in
                        model.start = min(model.end - gap, max(0, model.start + (direction == .increment ? 0.1 : -0.1)))
                        model.seekPreview(model.start)
                    }
                handle("Trim end", time: model.end).offset(x: right - 8)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if dragEnd == nil { dragEnd = model.end }
                        model.end = max(model.start + gap, min(total, (dragEnd ?? model.end) + value.translation.width / width * total))
                        model.seekPreview(model.end); hoverTime = model.end
                    }.onEnded { _ in dragEnd = nil; hoverTime = nil })
                    .accessibilityAdjustableAction { direction in
                        model.end = max(model.start + gap, min(total, model.end + (direction == .increment ? 0.1 : -0.1)))
                        model.seekPreview(model.end)
                    }
                if let time = hoverTime {
                    TimelineThumbnail(url: model.url, time: time, selectionDuration: model.end - model.start)
                        .position(x: min(max(80, time / total * width + 8), max(80, geometry.size.width - 80)), y: -60)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 28)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    if dragStart == nil && dragEnd == nil { hoverTime = min(total, max(0, (point.x - 8) / width * total)) }
                case .ended: if dragStart == nil && dragEnd == nil { hoverTime = nil }
                }
            }
        }.frame(height: 28)
    }

    private func handle(_ title: String, time: Double) -> some View {
        Capsule().fill(.white).frame(width: 4, height: 18)
            .frame(width: 16, height: 28).contentShape(Rectangle())
            .accessibilityElement().accessibilityLabel(title).accessibilityValue(Self.timestamp(time))
            .help("\(title): \(Self.timestamp(time)) · Drag to trim")
    }

    static func timestamp(_ value: Double) -> String {
        let value = value.isFinite ? max(0, value) : 0
        return String(format: "%d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
}

private struct TimelineThumbnail: View {
    let url: URL
    let time: Double
    let selectionDuration: Double
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image { Image(nsImage: image).resizable().scaledToFit() }
            }.frame(width: 152, height: 86)
            Text("\(EditorTimelineView.timestamp(time))  (\(EditorTimelineView.timestamp(selectionDuration)))")
                .font(.system(size: 10)).monospacedDigit().padding(.vertical, 5)
        }
        .background(.black.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 6, y: 2)
        .task(id: Int(time * 10)) {
            do {
                try await Task.sleep(for: .milliseconds(80))
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 304, height: 172)
                let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                try Task.checkCancellation()
                image = NSImage(cgImage: frame.image, size: .zero)
            } catch { /* Thumbnail is optional; playback remains available. */ }
        }
    }
}
