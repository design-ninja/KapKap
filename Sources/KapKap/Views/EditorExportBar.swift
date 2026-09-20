import SwiftUI
import CaptureCore

struct EditorExportBar: View {
    @Bindable var model: EditorStore
    @State private var showOptions = false
    private enum Field { case width, height, fps }
    @FocusState private var focus: Field?
    private var unavailable: Bool { !model.loaded || model.exporting }

    var body: some View {
        HStack(spacing: 8) {
            sizeField
            frameRateField
            Button { showOptions.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(GlyphButtonStyle())
                .help("Quality and export settings").accessibilityLabel("Export settings")
                .popover(isPresented: $showOptions, arrowEdge: .top) { ExportOptionsView(model: model) }
                .disabled(unavailable)
            Spacer(minLength: 16)
            if model.exporting {
                ProgressView().controlSize(.small)
                Text("Exporting…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                Button("Cancel") { model.cancelExport() }.controlSize(.small)
            } else {
                if let url = model.exportedURL { result(url) }
                MenuField(title: model.format.rawValue, width: 84) {
                    Picker("Format", selection: $model.format) {
                        ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.inline)
                }.help("Export format").disabled(unavailable)
                ExportAction(model: model).disabled(unavailable)
            }
        }
        .padding(.horizontal, 14).frame(height: 56)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(white: 0.13)
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
            }
        }
    }

    private var sizeField: some View {
        FieldSurface {
            TextField("", value: Binding(get: { model.width }, set: { model.setExportWidth($0) }),
                      format: .number.grouping(.never))
                .focused($focus, equals: .width)
                .modifier(FieldText(width: 50, focused: focus == .width))
                .accessibilityLabel("Export width")
            Text("×").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            TextField("", value: Binding(get: { model.exportHeight }, set: { model.setExportHeight($0) }),
                      format: .number.grouping(.never))
                .focused($focus, equals: .height)
                .modifier(FieldText(width: 50, focused: focus == .height))
                .accessibilityLabel("Export height")
            ExportSizeMenu(model: model)
        }
        .help("Export size in pixels · the aspect ratio is preserved")
        .disabled(unavailable)
    }

    private var frameRateField: some View {
        FieldSurface {
            TextField("", value: Binding(get: { model.fps }, set: { model.fps = FrameRate.clamp($0) }),
                      format: .number.grouping(.never))
                .focused($focus, equals: .fps)
                .modifier(FieldText(width: 32, focused: focus == .fps))
                .accessibilityLabel("Export frame rate")
            Text("fps").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            ChevronMenu {
                Picker("Frame rate", selection: $model.fps) {
                    ForEach(model.frameRateChoices, id: \.self) { Text("\($0) fps").tag($0) }
                }.pickerStyle(.inline)
            }.accessibilityLabel("Frame rate presets")
        }
        .help("Frames per second")
        .disabled(unavailable)
    }

    private func result(_ url: URL) -> some View {
        Menu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            ShareLink(item: url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                Text(model.copiedToClipboard ? "Copied" : "Saved")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.green)
            .padding(.horizontal, 9).frame(height: 24)
            .background(Color.green.opacity(0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(model.copiedToClipboard ? "Copied to clipboard" : "Saved")
        .accessibilityLabel(model.copiedToClipboard ? "Copied to clipboard" : "Saved")
    }
}

/// Primary action and its destination in one control: the label always says where the export goes.
private struct ExportAction: View {
    @Bindable var model: EditorStore
    @Environment(\.isEnabled) private var enabled
    @State private var menuHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if model.copyDestination { model.copyToClipboard() } else { model.chooseExport() }
            } label: {
                Text(model.copyDestination ? "Copy to Clipboard" : "Save to File…")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 30)
            }
            .buttonStyle(SplitActionStyle())
            .keyboardShortcut("e", modifiers: .command)
            .help("Export the trimmed recording (⌘E)")
            Rectangle().fill(.black.opacity(0.22)).frame(width: 1, height: 30)
            Menu {
                Picker("Destination", selection: $model.copyDestination) {
                    Text("Copy to Clipboard").tag(true)
                    Text("Save to File…").tag(false)
                }.pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white).frame(width: 24, height: 30)
                    .background(Color.white.opacity(menuHovered && enabled ? 0.13 : 0),
                                in: UnevenRoundedRectangle(bottomTrailingRadius: ControlSurface.radius,
                                                           topTrailingRadius: ControlSurface.radius))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .onHover { menuHovered = $0 }
            .help("Choose where the export goes")
            .accessibilityLabel("Export destination")
        }
        .background(Color.accentColor.opacity(enabled ? 1 : 0.3), in: RoundedRectangle(cornerRadius: ControlSurface.radius))
    }
}
