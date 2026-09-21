import XCTest
import AppKit
import Carbon
@testable import KapKap

final class RecordingHotKeyTests: XCTestCase {
    @MainActor func testConflictKeepsExistingShortcutAndPersistedChoice() throws {
        let suite = "KapKap-shortcut-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = RecordingShortcut(keyCode: UInt32(kVK_F17), modifiers: UInt32(cmdKey | controlKey | optionKey), key: "F17")
        let occupied = RecordingShortcut(keyCode: UInt32(kVK_F18), modifiers: original.modifiers, key: "F18")
        defaults.set(try JSONEncoder().encode(original), forKey: "recordingShortcut")
        let service = RecordingHotKey(defaults: defaults)
        XCTAssertEqual(service.register(), noErr)
        var external: EventHotKeyRef?
        XCTAssertEqual(RegisterEventHotKey(occupied.keyCode, occupied.modifiers,
            EventHotKeyID(signature: 0x54455354, id: 1), GetApplicationEventTarget(), 0, &external), noErr)
        defer { if let external { UnregisterEventHotKey(external) } }
        XCTAssertFalse(service.update(occupied))
        XCTAssertNotNil(service.error)
        XCTAssertEqual(service.shortcut, original)
        XCTAssertEqual(RecordingHotKey(defaults: defaults).shortcut, original)
        var duplicate: EventHotKeyRef?
        XCTAssertNotEqual(RegisterEventHotKey(original.keyCode, original.modifiers,
            EventHotKeyID(signature: 0x54455354, id: 2), GetApplicationEventTarget(), 0, &duplicate), noErr)
        if let duplicate { UnregisterEventHotKey(duplicate) }
        let replacement = RecordingShortcut(keyCode: UInt32(kVK_F19), modifiers: original.modifiers, key: "F19")
        XCTAssertTrue(service.update(replacement))
        XCTAssertNil(service.error)
        XCTAssertEqual(RecordingHotKey(defaults: defaults).shortcut, replacement)
        var released: EventHotKeyRef?
        XCTAssertEqual(RegisterEventHotKey(original.keyCode, original.modifiers,
            EventHotKeyID(signature: 0x54455354, id: 3), GetApplicationEventTarget(), 0, &released), noErr)
        if let released { UnregisterEventHotKey(released) }
    }

    func testShortcutInputRequiresCommandOrControl() throws {
        func event(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "r", charactersIgnoringModifiers: "r",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_R)))
        }
        XCTAssertNil(RecordingShortcut(event: try event([])))
        XCTAssertNil(RecordingShortcut(event: try event([.shift, .option])))
        XCTAssertEqual(RecordingShortcut(event: try event([.command, .control, .option])), .standard)
    }

    @MainActor func testSecondShortcutKeepsItsOwnChoiceAndCannotTakeTheFirstOnesKeys() throws {
        let suite = "KapKap-shortcut-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let modifiers = UInt32(cmdKey | controlKey | optionKey)
        let recordKeys = RecordingShortcut(keyCode: UInt32(kVK_F13), modifiers: modifiers, key: "F13")
        let selectKeys = RecordingShortcut(keyCode: UInt32(kVK_F14), modifiers: modifiers, key: "F14")
        let record = RecordingHotKey(defaults: defaults, standard: recordKeys)
        let select = RecordingHotKey(defaults: defaults, preferenceKey: "selectionShortcut", id: 2, standard: selectKeys)
        XCTAssertEqual(record.register(), noErr)
        XCTAssertEqual(select.register(), noErr)
        XCTAssertFalse(select.update(recordKeys))
        XCTAssertEqual(select.shortcut, selectKeys)
        let moved = RecordingShortcut(keyCode: UInt32(kVK_F15), modifiers: modifiers, key: "F15")
        XCTAssertTrue(select.update(moved))
        XCTAssertEqual(RecordingHotKey(defaults: defaults, preferenceKey: "selectionShortcut", id: 2, standard: selectKeys).shortcut, moved)
        XCTAssertEqual(RecordingHotKey(defaults: defaults, standard: recordKeys).shortcut, recordKeys)
    }
}
