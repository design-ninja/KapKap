import Foundation
import CaptureCore

struct RecordingSettings {
    var fps = FrameRate.choices.contains(UserDefaults.standard.integer(forKey: "fps"))
        ? UserDefaults.standard.integer(forKey: "fps") : FrameRate.standard
    var microphone = UserDefaults.standard.bool(forKey: "microphone")
    var microphoneID = UserDefaults.standard.string(forKey: "microphoneID")
    var showCursor = UserDefaults.standard.object(forKey: "showCursor") as? Bool ?? true
    var highlightClicks = UserDefaults.standard.bool(forKey: "highlightClicks")

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(fps, forKey: "fps")
        defaults.set(microphone, forKey: "microphone")
        defaults.set(microphoneID, forKey: "microphoneID")
        defaults.set(showCursor, forKey: "showCursor")
        defaults.set(highlightClicks, forKey: "highlightClicks")
    }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
