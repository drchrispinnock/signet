import Foundation
import Sparkle

/// Self-updating through Sparkle, the way iTerm2 and NetNewsWire do it: the app checks the appcast
/// named by `SUFeedURL` in Info.plist once a day, offers any newer release it finds, and installs
/// it in place. Updates are verified against `SUPublicEDKey`, so only archives signed with our
/// private key (and, being notarised, also by Apple) are ever installed.
///
/// Owns the one `SPUStandardUpdaterController`, which provides Sparkle's standard alerts and
/// progress window. The updater is not started under the test host so tests never hit the network
/// or put up a dialog.
@MainActor
@Observable
final class UpdaterService {
    /// False while a check or an install is already under way.
    private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(starting: Bool = true) {
        controller = SPUStandardUpdaterController(startingUpdater: starting,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
        }
    }

    /// "Check for Updates…": always reports the result, even when there is nothing new.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// The daily background check. Defaults to on (`SUEnableAutomaticChecks`); Sparkle keeps the
    /// user's choice in UserDefaults.
    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// Download and stage updates silently, installing on the next relaunch. Off by default so an
    /// update never arrives while the user is in the middle of signing something.
    var automaticallyDownloadsUpdates: Bool {
        get {
            access(keyPath: \.automaticallyDownloadsUpdates)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyDownloadsUpdates) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    /// When the last check ran, for Settings.
    var lastUpdateCheckDate: Date? {
        access(keyPath: \.lastUpdateCheckDate)
        return controller.updater.lastUpdateCheckDate
    }

    /// Where updates come from, for Settings.
    var feedURL: URL? {
        controller.updater.feedURL
    }
}
