import Foundation
import Observation
import Sparkle

/// Updates from GitHub Releases through Sparkle: the feed is `appcast.xml` on the latest release,
/// and every update must carry a signature made with the key whose public half is in Info.plist.
@MainActor @Observable
final class Updater {
    private(set) var canCheckForUpdates = false
    /// Development builds carry a placeholder key, so they never check: only release builds update.
    let isAvailable: Bool
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isAvailable = !(key?.isEmpty ?? true) && key != Self.placeholderKey
        controller = SPUStandardUpdaterController(startingUpdater: isAvailable,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    static let placeholderKey = "SPARKLE_PUBLIC_KEY"

    /// Sparkle keeps this preference in its own defaults; read and write it through the updater.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
