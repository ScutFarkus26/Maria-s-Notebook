import Foundation
import OSLog

// Signing in and out: through ParentLocker's own form, kept in the Keychain,
// with a refused password, or a sign-in ParentLocker wants a person for,
// remembered so the app never signs in by itself with what ParentLocker
// won't take. And the whole-class send waiting for a sign-in.

extension ParentLockerSync {

    // MARK: - Signing in and out

    /// The site the guide picked.
    var site: String { store.site }

    /// Signs in through ParentLocker's own form, out of sight, and keeps the
    /// sign-in (`completeSignIn`).
    func signIn(email: String, password: String) async throws {
        let credential = ParentLockerKeychain.Credential(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password
        )
        let site = site
        let cookies = try await dependencies.signIn(credential, site)
        try await completeSignIn(credential, cookies: cookies, site: site)
    }

    /// Keeps a sign-in the site's form accepted: first proves the attendance
    /// page loads with these cookies, then saves the password (synced to the
    /// person's own devices) and the cookies (this device only), and sends
    /// anything owed. The password is saved only once ParentLocker took it,
    /// so a mistyped one never replaces a working one on the other devices.
    func completeSignIn(
        _ credential: ParentLockerKeychain.Credential, cookies: [ParentLockerCookie], site: String
    ) async throws {
        let secrets = dependencies.secrets
        try secrets.saveCookies(cookies, site: site)
        let transport = makeTransport(site: site, cookies: cookies)
        do {
            _ = try await transport.courses(on: nil)
            // Cancelled while the class list loaded (the sheet closed): nothing is kept.
            if Task.isCancelled { throw ParentLockerSignInError.cancelled }
        } catch {
            try? secrets.deleteCookies(site: site)
            throw error
        }
        try secrets.savePassword(credential, site: site)
        forgetRefusedPassword()
        Self.logger.info("ParentLocker: signed in")
        isSignedIn = true
        signInNeedsYou = false
        awaitsSignIn = false
        status.state = .idle
        status.details = nil
        // This device's changes that failed for want of the sign-in go now.
        if localDue == nil {
            catchUpChildren.formUnion(localChanges.keys)
            localChanges = [:]
        }
        releaseWholeClass(at: clock.now)
        releaseCatchUp()
        refreshStatus()
    }

    /// The sign-in sheet closed. Nothing asks for a sign-in again by itself,
    /// and a Send Now that was waiting for it doesn't go: the person decided
    /// against it. Close Arrival & Send's stays owed, for a later sign-in or
    /// the guide's backstop. Safe to call however the sheet closed: a
    /// sign-in has already released what waited.
    func signInDismissed() {
        awaitsSignIn = false
        guard wholeClass?.reason == .sendNow, wholeClass?.due == nil else { return }
        wholeClass = nil
        saveOwed()
        reschedule()
    }

    /// Send Now on a device that needs a sign-in: today's whole class goes
    /// once someone signs in (`completeSignIn`), unless the sheet closes
    /// first. A Close Arrival & Send already waiting covers it.
    func sendAfterSignIn() {
        rollOwedDay(to: clock.now)
        if wholeClass?.reason == .backstop { backstopDay = nil }
        if wholeClass?.reason != .closeArrival { wholeClass = ParentLockerWholeClass(reason: .sendNow, due: nil) }
        awaitsSignIn = true
        saveOwed()
        reschedule()
    }

    /// Sign Out: deletes the password everywhere it synced (so the person's
    /// other devices sign out on their next check) and this device's cookies.
    /// Throws, still signed in, when the Keychain won't delete the password:
    /// it would stay on the person's other devices.
    func signOut() throws {
        do {
            try dependencies.secrets.deletePassword(site: site)
        } catch {
            Self.logger.error("ParentLocker: Sign Out failed (\(String(describing: error), privacy: .public))")
            throw error
        }
        Self.logger.info("ParentLocker: signed out")
        signedOutHere()
    }

    /// Reads whether a password is saved for the site. One deleted on another
    /// device (Sign Out there) takes this device's cookies with it. Only a
    /// password that isn't there signs out: a Keychain that can't be read
    /// right now (the device locked since restart, say) leaves things as they are.
    func refreshSignIn() {
        let site = site
        let hasPassword: Bool
        do {
            hasPassword = try dependencies.secrets.hasPassword(site: site)
        } catch {
            Self.logger.error("ParentLocker: unreadable sign-in (\(String(describing: error), privacy: .public))")
            return
        }
        if !hasPassword {
            if isSignedIn { signedOutHere() } else { try? dependencies.secrets.deleteCookies(site: site) }
        }
        isSignedIn = hasPassword
        savedPasswordRefused = hasPassword && refusalStands(site: site)
    }

    /// Whether the saved password is the one ParentLocker refused: none saved since.
    private func refusalStands(site: String) -> Bool {
        guard let refused = dependencies.refusals.refused(site: site),
              let saved = try? dependencies.secrets.passwordModified(site: site) else { return false }
        return saved == refused
    }

    /// A password ParentLocker took, or a new one saved: none is refused.
    func forgetRefusedPassword() {
        dependencies.refusals.setRefused(nil, site: site)
        savedPasswordRefused = false
    }
}
