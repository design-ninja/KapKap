import AppKit
import Carbon

struct RecordingShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let standard = RecordingShortcut(keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey | cmdKey), key: "R")

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.contains(.command) || flags.contains(.control),
              let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = (flags.contains(.command) ? UInt32(cmdKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
        key = characters
    }
}
