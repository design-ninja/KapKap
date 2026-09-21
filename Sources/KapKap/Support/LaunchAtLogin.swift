import Observation
import ServiceManagement

/// Starts KapKap when the user logs in, through the system's own login item list.
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var enabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    init() { refresh() }

    /// The user can change it in System Settings at any time, so read the status fresh.
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func set(_ enable: Bool) {
        error = nil
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
