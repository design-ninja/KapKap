import SwiftUI

/// The one record button: same shape, same animation, whichever set of controls the panel shows.
struct RecordButton: View {
    @Bindable var store: CaptureStore
    let action: () -> Void
    private let recordingRed = Color(.sRGB, red: 1, green: 0.23, blue: 0.23, opacity: 1)

    var body: some View {
        Button(action: action) {
            ZStack {
                if store.phase == .starting || store.phase == .stopping {
                    ProgressView().controlSize(.small)
                } else if store.active {
                    RoundedRectangle(cornerRadius: 4).fill(recordingRed).frame(width: 24, height: 24)
                } else {
                    Circle().fill(recordingRed).frame(width: 40, height: 40)
                }
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(RecordingButtonStyle())
    }
}
