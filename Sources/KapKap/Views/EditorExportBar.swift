import SwiftUI
import CaptureCore

struct EditorExportBar: View {
    @Bindable var model: EditorStore
    @State private var clipboard = true
    @State private var showOptions = false
    private var unavailable: Bool { !model.loaded || model.exporting }

    var body: some View {
        HStack(spacing: 10) {
            Text("Size").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Width", value: Binding(get: { model.width }, set: { model.setExportWidth($0) }), format: .number.grouping(.never))
                    .frame(width: 52).accessibilityLabel("Export width")
                Text("×").foregroundStyle(.tertiary)
                TextField("Height", value: Binding(get: { model.exportHeight }, set: { model.setExportHeight($0) }), format: .number.grouping(.never))
                    .frame(width: 52).accessibilityLabel("Export height")
            }.help("Pixel dimensions · aspect ratio is preserved").disabled(unavailable)
            ExportSizeMenu(model: model).disabled(unavailable)
            Text("FPS").foregroundStyle(.secondary).padding(.leading, 4)
            TextField("FPS", value: Binding(get: { model.fps }, set: { model.fps = min(60, max(1, $0)) }), format: .number.grouping(.never))
                .frame(width: 34).accessibilityLabel("Export frame rate").disabled(unavailable)
            Button { showOptions.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).help("Quality and export settings").accessibilityLabel("Export settings")
                .popover(isPresented: $showOptions) { ExportOptionsView(model: model) }.disabled(unavailable)
            Spacer(minLength: 8)
            if model.exporting {
                ProgressView().controlSize(.mini)
                Button("Cancel") { model.cancelExport() }
            } else {
                if let url = model.exportedURL {
                    Menu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        ShareLink(item: url)
                    } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help(model.copiedToClipboard ? "Copied to clipboard" : "Saved")
                    .accessibilityLabel(model.copiedToClipboard ? "Copied to clipboard" : "Saved")
                }
                Text("Destination").foregroundStyle(.secondary)
                Picker("Format", selection: $model.format) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 74).help("Export format").disabled(unavailable)
                Picker("Destination", selection: $clipboard) {
                    Text("Copy to Clipboard").tag(true)
                    Text("Save to File…").tag(false)
                }.labelsHidden().frame(width: 150).disabled(unavailable)
                Button("Export") {
                    if clipboard { model.copyToClipboard() } else { model.chooseExport() }
                }.frame(minWidth: 64).keyboardShortcut("e", modifiers: .command).disabled(unavailable)
            }
        }
        .font(.system(size: 11)).controlSize(.small)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 16).frame(height: 48)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }
}
