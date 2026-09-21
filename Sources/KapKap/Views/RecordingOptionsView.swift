import AVFoundation
import CaptureCore
import SwiftUI

struct RecordingOptionsView<Source: View>: View {
    @Binding var settings: RecordingSettings
    private let source: Source

    init(settings: Binding<RecordingSettings>, @ViewBuilder source: () -> Source) {
        _settings = settings
        self.source = source()
    }

    @State private var devices: [AVCaptureDevice] = []

    var body: some View {
        VStack(spacing: 4) {
            source
            HStack(spacing: 10) {
                Text("Frame rate")
                Spacer(minLength: 12)
                Picker("Frame rate", selection: $settings.fps) {
                    ForEach(FrameRate.choices.reversed(), id: \.self) { Text("\($0)").tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
                Text("fps").foregroundStyle(.secondary)
            }.frame(minHeight: 30)
            Divider()
            option("Show cursor", value: $settings.showCursor)
            Divider()
            option("Highlight clicks", value: $settings.highlightClicks)
            Divider()
            option("Microphone", value: $settings.microphone)
            if settings.microphone {
                Divider()
                HStack(spacing: 10) {
                    Text("Audio input")
                    Spacer(minLength: 12)
                    Picker("Audio input", selection: $settings.microphoneID) {
                        Text("System default").tag(String?.none)
                        ForEach(devices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device.uniqueID))
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .frame(maxWidth: 180, alignment: .trailing)
                }.frame(minHeight: 30)
            }

        }
        .font(.system(size: 12)).controlSize(.small)
        .task {
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        }
        .onDisappear { settings.save() }
    }

    private func option(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            // Even the mini switch outweighs the 12 pt labels, so it is drawn a notch smaller.
            NativeSwitch(isOn: value, label: title)
                .fixedSize()
                .scaleEffect(0.8, anchor: .trailing)
        }.frame(maxWidth: .infinity, minHeight: 30)
    }
}


extension RecordingOptionsView where Source == EmptyView {
    init(settings: Binding<RecordingSettings>) {
        self.init(settings: settings) { EmptyView() }
    }
}
