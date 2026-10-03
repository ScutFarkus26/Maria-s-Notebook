import CloudKit

extension AssistantBootstrapper {
    /// What one account check means for the stack. The first check that can
    /// tell decides whether it came up without a usable account: no account,
    /// a restricted one, or one temporarily unavailable (an Apple Account
    /// waiting for its password), for all of which the container's CloudKit
    /// setup fails ("Unable to initialize without a valid iCloud account",
    /// seen on a simulator 2026-09-29). Only "couldn't determine", the check
    /// itself failing, decides nothing (`decided` false), so the next check
    /// decides instead of that hiccup costing a rebuild. After that, the
    /// account arriving is the one reason to rebuild, once.
    nonisolated static func accountDecision(
        checkedSinceBuild: Bool,
        needsAccount: Bool,
        status: CKAccountStatus
    ) -> AccountDecision {
        guard checkedSinceBuild else {
            switch status {
            case .available: return AccountDecision(needsAccount: false)
            case .noAccount, .restricted, .temporarilyUnavailable: return AccountDecision(needsAccount: true)
            default: return AccountDecision(needsAccount: false, decided: false)
            }
        }
        if needsAccount, status == .available { return AccountDecision(needsAccount: false, rebuild: true) }
        return AccountDecision(needsAccount: needsAccount)
    }

    nonisolated struct AccountDecision: Equatable {
        /// The stack came up without a usable account and waits for one.
        var needsAccount: Bool
        var rebuild = false
        /// False when the check couldn't tell, so the next one decides.
        var decided = true
    }
}
