import SwiftUI
import CaptureCore

struct ExportOptionsView: View {
    @Bindable var model: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export settings").font(.system(size: 13, weight: .semibold))
            if model.format == .mp4 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("Quality", selection: $model.quality) {
                        ForEach(MP4Quality.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .disabled(model.keepOriginal && model.canKeepOriginal)
                }
                if model.canKeepOriginal {
                    Toggle("Keep original file", isOn: $model.keepOriginal)
                        .toggleStyle(.switch)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Text("\(model.width) × \(model.exportHeight) · \(model.fps) fps · \(EditorTimelineView.timestamp(model.end - model.start, precise: false))")
                    .monospacedDigit().lineLimit(1)
                Image(systemName: model.exportsAudio ? "speaker.wave.2" : "speaker.slash")
                    .help(model.exportsAudio ? "Audio" : "No audio")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
        .font(.system(size: 12)).controlSize(.small)
        .padding(16).frame(width: 264).disabled(model.exporting)
    }
}
