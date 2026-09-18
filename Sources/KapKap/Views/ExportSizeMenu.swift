import SwiftUI

struct ExportSizeMenu: View {
    @Bindable var model: EditorStore
    private let percentages = [100, 75, 50, 33, 25, 20, 10]

    private func width(for percent: Int) -> Int {
        max(2, Int(Double(model.sourceWidth) * Double(percent) / 100) / 2 * 2)
    }

    var body: some View {
        Menu {
            Picker("Size", selection: Binding(get: { model.width }, set: { model.setExportWidth($0) })) {
                ForEach(percentages, id: \.self) { percent in
                    let width = width(for: percent)
                    let height = max(2, Int((Double(width) * Double(model.sourceHeight) / Double(model.sourceWidth) / 2).rounded()) * 2)
                    Text("\(width) × \(height) (\(percent == 100 ? "Original" : "\(percent)%"))").tag(width)
                }
                if !percentages.contains(where: { width(for: $0) == model.width }) {
                    Text("\(model.width) × \(model.exportHeight) (Custom)").tag(model.width)
                }
            }.pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                .frame(width: 16, height: 22).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Export size presets").accessibilityLabel("Export size presets")
    }
}
