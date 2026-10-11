import Foundation

/// Developer switches that must never stay on by accident (S11). Verbose dApp diagnostics make the
/// SDK log decrypted relay traffic, so the switch is armed for one launch only: Settings sets it,
/// the next launch consumes it, and it is off again after that.
enum DeveloperSettings {
    static let dappDiagnosticsKey = "dappDiagnosticsNextLaunch"

    /// Read once at launch, and cleared so it does not outlive this run.
    static let dappDiagnostics: Bool = {
        let defaults = UserDefaults.standard
        let armed = defaults.bool(forKey: dappDiagnosticsKey)
        if armed { defaults.removeObject(forKey: dappDiagnosticsKey) }
        return armed
    }()

    static var dappDiagnosticsArmed: Bool {
        get { UserDefaults.standard.bool(forKey: dappDiagnosticsKey) }
        set {
            if newValue { UserDefaults.standard.set(true, forKey: dappDiagnosticsKey) } else { UserDefaults.standard.removeObject(forKey: dappDiagnosticsKey) }
        }
    }
}
