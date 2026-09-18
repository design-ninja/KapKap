import SwiftUI
import AVKit

struct EditorView: View {
    @State private var model: EditorStore

    init(url: URL) { _model = State(initialValue: EditorStore(url: url)) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                RecordingPlayerView(player: model.player)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110).allowsHitTesting(false)
                playbackControls.padding(.horizontal, 20).padding(.bottom, 16)
            }
            .frame(minHeight: 260, maxHeight: .infinity)
            .background(.black)
            EditorExportBar(model: model)
        }
        .frame(minWidth: 760, minHeight: 330)
        .background(EditorWindowLayout(title: model.url.lastPathComponent,
                                       aspectRatio: model.loaded ? Double(model.sourceWidth) / Double(model.sourceHeight) : nil))
        .navigationTitle(model.url.lastPathComponent)
        .task { await model.load() }
        .onDisappear { model.player.pause(); model.cancelExport() }
        .alert("KapKap", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error?.text ?? "") }
    }

    private var playbackControls: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            HStack(spacing: 14) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.player.rate > 0 ? "pause.fill" : "play.fill").frame(width: 18, height: 24)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Play / pause (Space)")
                .accessibilityLabel(model.player.rate > 0 ? "Pause" : "Play selection")
                Text(EditorTimelineView.timestamp(model.player.currentTime().seconds))
                    .monospacedDigit().frame(width: 56, alignment: .leading)
                EditorTimelineView(model: model, playhead: model.player.currentTime().seconds)
                Button { model.start = 0; model.end = model.duration; model.seekPreview(0) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }.help("Reset trim").accessibilityLabel("Reset trim")
                    .disabled(model.start == 0 && model.end == model.duration)
                Button { model.muted.toggle(); model.player.isMuted = model.muted } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }.help(model.muted ? "Include audio" : "Mute audio")
                    .accessibilityLabel(model.muted ? "Include audio" : "Mute audio")
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }.help("Full screen").accessibilityLabel("Full screen")
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
            .disabled(!model.loaded || model.exporting)
        }
    }
}
