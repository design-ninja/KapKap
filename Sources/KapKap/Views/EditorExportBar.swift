import SwiftUI
import CaptureCore

struct EditorExportBar: View {
    @Bindable var model: EditorStore
    private enum Field { case width, height }
    @FocusState private var focus: Field?
    private var unavailable: Bool { !model.loaded || model.exporting }

    var body: some View {
        HStack(spacing: 8) {
            sizeField
            frameRateField
            MenuField(title: model.format.rawValue, width: 84) {
                Picker("Format", selection: $model.format) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.inline)
            }.help("Export format").disabled(unavailable)
            if model.offersQuality { qualityField }
            summary
            Spacer(minLength: 16)
            if model.exporting {
                ProgressView(value: model.exportProgress).progressViewStyle(.circular).controlSize(.mini)
                Text("Exporting \(Int(model.exportProgress * 100))%")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: Int(model.exportProgress * 100))
                Button("Cancel") { model.cancelExport() }.buttonStyle(FieldButtonStyle())
            } else {
                if let url = model.exportedURL { result(url) }
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

    /// The recording's own rate comes first, followed by lower export rates.
    private var frameRateField: some View {
        MenuField(title: frameRateTitle(model.fps), width: 130) {
            Picker("Frame rate", selection: $model.fps) {
                Text("\(model.sourceFPS) fps (Native)").tag(model.sourceFPS)
                ForEach(model.frameRateChoices.filter { $0 < model.sourceFPS }.sorted(), id: \.self) {
                    Text("\($0) fps").tag($0)
                }
            }.pickerStyle(.inline)
        }
        .help("Export frame rate · Original: \(model.sourceFPS) fps")
        .accessibilityLabel("Export frame rate")
        .disabled(unavailable)
    }

    /// Only video formats trade size for detail; GIF and APNG have nothing to choose. MP4 and HEVC
    /// can also trade size for speed on the Mac's media engine.
    private var qualityField: some View {
        MenuField(title: Self.title(for: model.quality) + (model.usesHardware ? " · Fast" : ""),
                  width: model.usesHardware ? 150 : 116) {
            Picker("Quality", selection: $model.quality) {
                ForEach(ExportQuality.allCases) { Text(Self.title(for: $0)).tag($0) }
            }.pickerStyle(.inline)
            if model.format.offersHardwareEncoding {
                Divider()
                Toggle("Fast Hardware Encoding", isOn: $model.hardware)
            }
        }
        .help(Self.summary(for: model.quality)
              + (model.usesHardware ? " Encoded on the Mac's media engine: several times faster, bigger file." : ""))
        .accessibilityLabel("Export quality")
        .disabled(unavailable)
    }

    /// The expected file size, dimmed while a new estimate is on its way.
    private var summary: some View {
        Text(model.estimatedBytes.map { "≈ " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "≈ …")
            .monospacedDigit().lineLimit(1)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(model.estimating ? 0.25 : 0.45))
            .animation(.easeOut(duration: 0.15), value: model.estimating)
            .padding(.leading, 4)
            .help("Estimated file size, from a short test encode with these settings")
            .accessibilityLabel(model.estimatedBytes.map { "Estimated size " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Estimating size")
            .task(id: model.estimateKey) { await model.estimateSize() }
    }

    private static func title(for quality: ExportQuality) -> String {
        switch quality {
        case .smaller: "Smaller file"
        case .balanced: "Balanced"
        case .best: "Best quality"
        }
    }

    private static func summary(for quality: ExportQuality) -> String {
        switch quality {
        case .smaller: "Lightest file, fine for sharing. Small text may blur."
        case .balanced: "Sharp picture at a reasonable size."
        case .best: "Closest to the recording. Largest file."
        }
    }

    private func frameRateTitle(_ fps: Int) -> String {
        fps == model.sourceFPS ? "\(fps) fps (Native)" : "\(fps) fps"
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
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
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
                Divider()
                Menu("Open With") {
                    ForEach(model.openWithApplications, id: \.self) { application in
                        Button { model.exportAndOpen(with: application) } label: {
                            Label { Text(Self.name(of: application)) } icon: { Image(nsImage: Self.icon(of: application)) }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white).frame(width: 24, height: 30)
                    .background(Color.white.opacity(menuHovered && enabled ? 0.13 : 0),
                                in: UnevenRoundedRectangle(bottomTrailingRadius: ControlSurface.radius,
                                                           topTrailingRadius: ControlSurface.radius))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .onHover { menuHovered = $0 }
            .help("Choose where the export goes, or open it in another app")
            .accessibilityLabel("Export destination")
        }
        .background(Color.accentColor.opacity(enabled ? 1 : 0.3), in: RoundedRectangle(cornerRadius: ControlSurface.radius))
    }

    private static func name(of application: URL) -> String {
        FileManager.default.displayName(atPath: application.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(of application: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: application.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
