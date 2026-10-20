import CloudKit
import OSLog

extension AssistantBootstrapper {
    private static let accountLogger = Logger.app(category: "bootstrap")

    /// Asks CloudKit about the account, and rebuilds the stack if it came up
    /// without one that's here now (`accountDecision`), or if the class
    /// store's setup failed for want of one (`rebuildIfSetupFailed`).
    func refreshAccountStatus() async {
        accountCheck += 1
        let check = accountCheck
        let status: CKAccountStatus
        do {
            status = try await fetchAccountStatus()
        } catch {
            // Unknown isn't a problem worth showing; keep what we had.
            Self.accountLogger.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            if check == accountCheck { retryUnknownAccount() }
            return
        }
        // A newer check is on its way, and its answer is the one that counts.
        guard check == accountCheck else { return }
        accountStatus = status
        retryUnknownAccount()
        guard coreDataStack != nil else { return }
        let decision = Self.accountDecision(
            checkedSinceBuild: accountCheckedSinceBuild,
            needsAccount: stackNeedsAccount,
            status: status
        )
        accountCheckedSinceBuild = decision.decided
        // Cleared before the rebuild awaits, so a second check arriving
        // meanwhile (the account-change loop and Check Again together)
        // doesn't rebuild again and pull the stores from under the first.
        stackNeedsAccount = decision.needsAccount
        if decision.rebuild {
            // The old stack's failed setup needs nothing more; the new
            // stack's own, if it fails too, gets its rebuild (`rebuildStack`).
            await rebuildStack(because: "iCloud account arrived after launch")
        } else {
            await rebuildIfSetupFailed()
        }
    }

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

    /// While the join screen may show and the account can't be told (the
    /// check failed, or CloudKit couldn't determine it), asks again every
    /// `accountRetryDelay`. The iCloud page spun on "Checking iCloud…" until
    /// she left the app and came back (bug hunt 2026-10-20 #25). Stops once
    /// an answer comes, or she's in a class.
    func retryUnknownAccount() {
        guard accountRetry == nil,
              Self.retriesAccountCheck(status: accountStatus, joinScreenMayShow: joinScreenMayShow) else { return }
        accountRetry = Task { [weak self, accountRetryDelay] in
            try? await Task.sleep(for: accountRetryDelay)
            guard let self, !Task.isCancelled else { return }
            accountRetry = nil
            guard Self.retriesAccountCheck(status: accountStatus, joinScreenMayShow: joinScreenMayShow) else { return }
            await refreshAccountStatus()
        }
    }

    /// Before the class (or the sample) is open: starting, or joining.
    private var joinScreenMayShow: Bool {
        switch phase {
        case .starting, .needsClassroom: !AssistantSampleClass.isChosen
        case .ready, .failed: false
        }
    }

    /// Whether to ask about the account again: it isn't known yet, or
    /// CloudKit couldn't tell, while the join screen may show.
    nonisolated static func retriesAccountCheck(status: CKAccountStatus?, joinScreenMayShow: Bool) -> Bool {
        joinScreenMayShow && (status == nil || status == .couldNotDetermine)
    }

    nonisolated struct AccountDecision: Equatable {
        /// The stack came up without a usable account and waits for one.
        var needsAccount: Bool
        var rebuild = false
        /// False when the check couldn't tell, so the next one decides.
        var decided = true
    }
}
