import AppKit
import Carbon
import SwiftUI

struct RecordingShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let standard = RecordingShortcut(keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey | cmdKey), key: "R")
    /// Opens the area selector from any app, like Kap's cropper shortcut.
    static let selection = RecordingShortcut(keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(controlKey | optionKey | cmdKey), key: "A")

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// The same keys for a menu item, so the menu shows the shortcut that is actually registered.
    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.lowercased().first, key.count == 1 else { return nil }
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
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
