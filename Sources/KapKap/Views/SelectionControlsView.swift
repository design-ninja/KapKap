import AppKit
import SwiftUI

/// The panel's controls while an area is being chosen; the record button is added by the panel itself.
struct SelectionControlsView: View {
    @Bindable var store: CaptureStore
    @Bindable var model: SelectionModel
    enum Dimension: Hashable { case width, height }
    /// The record button sits in the middle of the panel, so the controls come in two halves.
    enum Side { case leading, trailing }
    var focus: FocusState<Dimension?>.Binding
    let side: Side

    var body: some View {
        Group {
            switch side {
            case .leading: leadingControls
            case .trailing: trailingControls
            }
        }
        // The canvas sets a crosshair; over the panel the pointer goes back to normal.
        .onHover { inside in if inside { NSCursor.arrow.set() } }
    }

    private var leadingControls: some View {
        HStack(spacing: 8) {
            Button { store.cancelSelection() } label: { Image(systemName: "arrow.left") }
                .help("Back (Esc)").accessibilityLabel("Back")
            // "Custom" is a state, not a choice: it shows when the lock or a swap left the
            // proportions off every preset, so it labels the field but never lists as an option.
            MenuField(title: model.ratio, width: 92) {
                Picker("Aspect ratio", selection: Binding<String?>(
                    get: { model.ratio == "Custom" ? nil : model.ratio },
                    set: { if let value = $0 { model.ratio = value } })) {
                    Text("Free").tag(String?.some("Free"))
                    ForEach(SelectionModel.ratios, id: \.self) { Text($0).tag(String?.some($0)) }
                }.pickerStyle(.inline)
            }
            .help("Aspect ratio").accessibilityLabel("Aspect ratio")
            .onChange(of: model.ratio) { _, value in model.applyRatio(value) }
            Button {
                model.locked.toggle()
                if model.locked { model.ratio = "Custom" }
            } label: { Image(systemName: model.locked ? "lock.fill" : "lock.open") }
                .help(model.locked ? "Unlock proportions" : "Lock proportions")
                .accessibilityLabel("Lock proportions").accessibilityValue(model.locked ? "On" : "Off")
        }
    }

    private var trailingControls: some View {
        FieldSurface {
            TextField("W", text: $model.widthText)
                .focused(focus, equals: .width)
                .modifier(FieldText(width: 52, focused: focus.wrappedValue == .width))
                .onSubmit { model.commitWidth() }
                .accessibilityLabel("Selection width in points")
            Text("×").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            TextField("H", text: $model.heightText)
                .focused(focus, equals: .height)
                .modifier(FieldText(width: 52, focused: focus.wrappedValue == .height))
                .onSubmit { model.commitHeight() }
                .accessibilityLabel("Selection height in points")
            Button { model.swapDimensions() } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(GlyphButtonStyle(size: 22, glyph: 11, radius: 5))
                .help("Swap width and height").accessibilityLabel("Swap width and height")
        }
        .help("Selection size in points")
        .disabled(!model.hasArea)
        .onChange(of: focus.wrappedValue) { previous, _ in
            if previous == .width { model.commitWidth() }
            if previous == .height { model.commitHeight() }
        }
    }

}
