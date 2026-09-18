import AppKit
import Carbon
import Observation

@MainActor @Observable
final class RecordingHotKey {
    private(set) var shortcut: RecordingShortcut
    private(set) var isListening = false
    private(set) var error: String?
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var focusObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var action: (() -> Void)?
    private static let preferenceKey = "recordingShortcut"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: Self.preferenceKey)
            .flatMap { try? JSONDecoder().decode(RecordingShortcut.self, from: $0) } ?? .standard
    }

    @discardableResult func register() -> OSStatus {
        guard hotKey == nil else { return noErr }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x4B41504B else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<RecordingHotKey>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in if !service.isListening { service.action?() } }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { report(status); return status }
        }
        let status = create(shortcut, reference: &hotKey)
        if status != noErr { report(status) }
        return status
    }

    @discardableResult func update(_ candidate: RecordingShortcut) -> Bool {
        error = nil
        if candidate == shortcut, hotKey != nil { return true }
        var replacement: EventHotKeyRef?
        let status = create(candidate, reference: &replacement)
        guard status == noErr else {
            error = "Could not register \(candidate.label) (error \(status)). Try another shortcut."
            return false
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        shortcut = candidate
        defaults.set(try? JSONEncoder().encode(candidate), forKey: Self.preferenceKey)
        return true
    }

    func beginListening() {
        guard !isListening else { return }
        error = nil
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        isListening = true
        let window = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self else { return event }
            guard event.window === window else { self.cancelListening(); return event }
            if event.keyCode == UInt16(kVK_Escape) { self.cancelListening(); return nil }
            guard !event.isARepeat else { return nil }
            guard let candidate = RecordingShortcut(event: event) else {
                self.error = "Use Command or Control with a letter or number."
                return nil
            }
            if self.update(candidate) { self.finishListening() }
            return nil
        }
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelListening() }
            }
    }

    func cancelListening() {
        guard isListening else { return }
        finishListening()
        _ = register()
    }

    private func finishListening() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
        isListening = false
    }

    private func create(_ value: RecordingShortcut, reference: inout EventHotKeyRef?) -> OSStatus {
        RegisterEventHotKey(value.keyCode, value.modifiers, EventHotKeyID(signature: 0x4B41504B, id: 1),
                           GetApplicationEventTarget(), 0, &reference)
    }

    private func report(_ status: OSStatus) {
        error = "Could not register \(shortcut.label) (error \(status)). Try another shortcut in Settings."
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
