import SwiftUI
import AVKit

struct EditorView: View {
    @State private var model: EditorStore
    @State private var fullScreen = false
    private let store: CaptureStore
    @Environment(\.dismiss) private var dismiss

    init(url: URL, store: CaptureStore) {
        _model = State(initialValue: EditorStore(url: url))
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                RecordingPlayerView(player: model.player)
                if !model.loaded { ProgressView().controlSize(.small) }
                playbackControls.padding(.horizontal, 14).padding(.bottom, 14)
            }
            .frame(minHeight: 260, maxHeight: .infinity)
            .background(.black)
            .alert("Discard this recording?", isPresented: $model.confirmingDiscard) {
                Button("Cancel", role: .cancel) { }
                Button("Keep in Recordings") {
                    model.approveClose()
                    dismiss()
                }
                Button("Discard", role: .destructive) {
                    model.discardRecording()
                    store.refreshLibrary()
                    model.approveClose()
                    dismiss()
                }
            } message: {
                Text("It has not been exported yet. Keeping it leaves the original in Recent recordings; discarding moves it to the Trash.")
            }
            EditorExportBar(model: model)
        }
        .frame(minWidth: 820, minHeight: 340)
        .background(EditorWindowLayout(url: model.url,
                                       aspectRatio: model.loaded ? Double(model.sourceWidth) / Double(model.sourceHeight) : nil,
                                       closeRequest: { model.requestClose() }))
        .navigationTitle(model.url.deletingPathExtension().lastPathComponent)
        .task { await model.load() }
        .onAppear { store.editorOpened() }
        .onDisappear {
            model.player.pause()
            model.cancelExport()
            store.editorClosed()
        }
        .alert("KapKap", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error?.text ?? "") }
    }

    private var playbackControls: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let time = model.player.currentTime().seconds
            HStack(spacing: 10) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.player.rate > 0 ? "pause.fill" : "play.fill")
                }
                .buttonStyle(GlyphButtonStyle(size: 30, glyph: 14))
                .keyboardShortcut(.space, modifiers: [])
                .help("Play or pause (Space)")
                .accessibilityLabel(model.player.rate > 0 ? "Pause" : "Play selection")

                HStack(spacing: 4) {
                    Text(EditorTimelineView.timestamp(time, precise: false)).foregroundStyle(.white)
                    Text("/").foregroundStyle(.white.opacity(0.3))
                    Text(EditorTimelineView.timestamp(model.duration, precise: false)).foregroundStyle(.white.opacity(0.5))
                }
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 92, alignment: .leading)
                .accessibilityLabel("Playback time")

                EditorTimelineView(model: model, playhead: time)

                // Always present so the timeline keeps its width while trimming.
                Button { model.resetTrim() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(GlyphButtonStyle())
                    .disabled(!model.trimmed)
                    .help("Reset trim").accessibilityLabel("Reset trim")
                Button { model.muted.toggle(); model.player.isMuted = model.muted } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(GlyphButtonStyle())
                .help(model.muted ? "Include audio" : "Mute audio")
                .accessibilityLabel(model.muted ? "Include audio" : "Mute audio")
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                    Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(GlyphButtonStyle())
                .help(fullScreen ? "Exit full screen" : "Full screen")
                .accessibilityLabel(fullScreen ? "Exit full screen" : "Full screen")
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                    fullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                    fullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            }
            .disabled(!model.loaded || model.exporting)
        }
    }
}
