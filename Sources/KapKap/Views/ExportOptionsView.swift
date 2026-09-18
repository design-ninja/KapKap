import SwiftUI
import CaptureCore

struct ExportOptionsView: View {
    @Bindable var model: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export settings").font(.system(size: 12, weight: .semibold))
            if model.format == .mp4 {
                Picker("Quality", selection: $model.quality) {
                    ForEach(MP4Quality.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(model.keepOriginal && model.canKeepOriginal)
                if model.canKeepOriginal {
                    Toggle("Keep original file", isOn: $model.keepOriginal)
                        .help("No compression. Usually a larger file.")
                }
            }
            Stepper("Frame rate: \(model.fps) fps", value: $model.fps, in: 1...60)
        }.font(.system(size: 12)).controlSize(.small).padding(16).frame(width: 240).disabled(model.exporting)
    }
}
