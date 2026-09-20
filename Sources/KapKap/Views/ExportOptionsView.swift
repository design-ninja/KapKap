import SwiftUI
import CaptureCore

struct ExportOptionsView: View {
    @Bindable var model: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    Text("Copies the recording untouched: no re-encoding, no quality loss, usually a larger file.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("\(model.format.rawValue) uses its own encoder preset. Quality options apply to MP4.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Output").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(summary).font(.system(size: 11).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12)).controlSize(.small)
        .padding(16).frame(width: 264).disabled(model.exporting)
    }

    private var summary: String {
        let length = EditorTimelineView.timestamp(model.end - model.start, precise: false)
        return "\(model.width) × \(model.exportHeight) · \(model.fps) fps · \(length) · \(model.muted ? "no audio" : "audio")"
    }
}
