import Foundation
import OSLog

// Signing in and out: through ParentLocker's own form, kept in the Keychain,
// with a refused password, or a sign-in ParentLocker wants a person for,
// remembered so the app never signs in by itself with what ParentLocker
// won't take; a run signs back in by itself only in front. And the
// whole-class send waiting for a sign-in.

extension ParentLockerSync {

    // MARK: - Signing in by itself

    /// Runs `body` with a transport carrying the saved cookies. Before
    /// anything, the password must still be there (Sign Out on another
    /// device removes it). With no cookies, or when the site has signed this
    /// device out, it signs in again with the saved password and runs
    /// `body` once more, but only in front.
    func withTransport<T>(
        site: String, _ body: (any ParentLockerTransport) async throws -> T
    ) async throws -> T {
        let secrets = dependencies.secrets
        let cookies: [ParentLockerCookie]
        do {
            guard try secrets.hasPassword(site: site) else { throw ParentLockerSyncStop.signedOut }
            cookies = try secrets.cookies(site: site)
        } catch let error as ParentLockerKeychain.KeychainError {
            Self.logger.error("ParentLocker: the keychain refused (\(String(describing: error), privacy: .public))")
            throw ParentLockerSyncStop.keychain
        }
        if cookies.isEmpty {
            return try await body(makeTransport(site: site, cookies: try await signInAgain(site: site)))
        }
        do {
            return try await body(makeTransport(site: site, cookies: cookies))
        } catch ParentLockerError.signedOut {
            Self.logger.info("ParentLocker: signed out by the site; signing in again")
            return try await body(makeTransport(site: site, cookies: try await signInAgain(site: site)))
        }
    }

    /// Signs in with the saved password through the site's form, out of
    /// sight, and keeps the new cookies. Never with a password ParentLocker
    /// refused: that one waits until a new one is saved, here or on another
    /// of the person's devices, so the school's site doesn't see it again and
    /// again. Never while ParentLocker wants a person at its sign-in (new
    /// terms, a reset) either: only a sign-in through the sheet, or a newer
    /// password saved on another of the person's devices, clears that (bug
    /// hunt 2026-10-13 afternoon, M9). Only in front: the web view stalls in
    /// the background.
    private func signInAgain(site: String) async throws -> [ParentLockerCookie] {
        let credential: ParentLockerKeychain.Credential?
        let saved: Date?
        do {
            credential = try dependencies.secrets.credential(site: site)
            saved = try dependencies.secrets.passwordModified(site: site)
        } catch {
            throw ParentLockerSyncStop.keychain
        }
        guard let credential else { throw ParentLockerSyncStop.signedOut }
        let password = saved ?? .distantPast
        guard dependencies.refusals.refused(site: site) != password else {
            savedPasswordRefused = true
            throw ParentLockerSyncStop.passwordRefused
        }
        if signInNeedsYou, needsYouPassword != password { signInNeedsYou = false }
        guard !signInNeedsYou else { throw ParentLockerSyncStop.needsYou }
        guard dependencies.isInForeground() else { throw ParentLockerSyncStop.notSentYet }
        // Cookies from a sign-in that a sign-out overtook aren't kept (bug hunt 2026-11-05 #25).
        let generation = signOuts.current
        let cookies: [ParentLockerCookie]
        do {
            cookies = try await dependencies.signIn(credential, site)
        } catch let error as ParentLockerSignInError {
            if error == .passwordRefused {
                Self.logger.error("ParentLocker: the saved password was refused; it won't be tried again")
                dependencies.refusals.setRefused(password, site: site)
                savedPasswordRefused = true
            } else if error == .needsYou || error == .cancelled {
                // A sign-in out of sight that ended cancelled is one no form
                // can finish by itself either (engine review of 2026-11-05).
                Self.logger.error("ParentLocker: the sign-in wants a person; it won't be tried again by itself")
                signInNeedsYou = true
                needsYouPassword = password
            }
            throw error.syncError
        }
        forgetRefusedPassword()
        let secrets = dependencies.secrets
        signOuts.ifNoneSince(generation) { try? secrets.saveCookies(cookies, site: site) }
        return cookies
    }

    /// A transport whose cookie changes are kept, unless a sign-out has come
    /// since it was made (bug hunt 2026-11-05 #25).
    func makeTransport(site: String, cookies: [ParentLockerCookie]) -> any ParentLockerTransport {
        let secrets = dependencies.secrets
        let signOuts = signOuts
        let generation = signOuts.current
        return dependencies.makeTransport(site, cookies) { changed in
            signOuts.ifNoneSince(generation) { try? secrets.saveCookies(changed, site: site) }
        }
    }

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
        signInDeclined = false
        status.state = .idle
        status.details = nil
        // This device's changes that failed for want of the sign-in go now.
        if localDue == nil {
            catchUpChildren.formUnion(localChanges.keys)
            localChanges = [:]
        }
        releaseWholeClass(at: clock.now)
        releaseCatchUp()
        // Today's marks as they stand, for the changes synced in from here
        // on, as at a start signed in (engine review of 2026-11-05).
        rememberMarks(store.day(today, withChildren: true))
        refreshStatus()
    }

    /// The sign-in sheet closed. Nothing asks for a sign-in again by itself,
    /// not even as each change takes the send owed and it fails again
    /// (`signInDeclined`), and a Send Now that was waiting for it doesn't
    /// go: the person decided against it. Close Arrival & Send's stays owed,
    /// for a later sign-in or the guide's backstop. Safe to call however the
    /// sheet closed: a sign-in has already released what waited.
    func signInDismissed() {
        awaitsSignIn = false
        signInDeclined = true
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
        signInDeclined = false
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

    /// Signed out, here or by Sign Out on another device: this device's
    /// cookies go (and none a reply brings later, #25), and nothing is owed
    /// any more but today's Close Arrival & Send, still waiting or the run
    /// that found her signed out (`keeping`). That one waits for a sign-in,
    /// as a retry: its Undo still stops it, and the guide's backstop still
    /// covers it (bug hunt 2026-11-05 #6).
    func signedOutHere(keeping job: ParentLockerJob? = nil) {
        let keepsCloseArrival = closeArrivalPending
            || job.map { $0.reason == .closeArrival && !$0.preview && isToday($0.day) } ?? false
        let secrets = dependencies.secrets
        let site = site
        signOuts.signOut { try? secrets.deleteCookies(site: site) }
        forgetRefusedPassword()
        isSignedIn = false
        signInNeedsYou = false
        localChanges = [:]
        localDue = nil
        catchUpChildren = []
        forgetImported(importedChildren)
        importedBefore = [:]
        earlyChanges = []
        forgetEarlyLocal(earlyLocal)
        lastSeen = [:]
        baselineRead = []
        deadlineDue = nil
        retry = nil
        otherDayRetries = [:]
        sending = [:]
        ownNotes = [:]
        standing = ParentLockerStanding()
        if keepsCloseArrival { wholeClass = ParentLockerWholeClass(reason: .closeArrival, due: nil, attempt: 1) }
        saveOwed()
        status = ParentLockerStatus(state: .signedOut)
        reschedule()
    }

    /// Reads whether a password is saved for the site. One deleted on another
    /// device (Sign Out there) takes this device's cookies with it. Only a
    /// password that isn't there signs out: a Keychain that can't be read
    /// right now (the device locked since restart, say) leaves things as they are.
    /// A newer password, saved here or on another of the person's devices,
    /// clears a refusal, and a sign-in ParentLocker wanted a person for: that
    /// person has signed in (review of the afternoon fixes, M9). Cookies
    /// left with no password go at the first read after `start` and when a
    /// sign-in goes, not on every return to the app (bug hunt 2026-11-03 #21).
    /// Signed out on another device with today's Close Arrival & Send still
    /// to go, this one asks for a sign-in to send it (review of the
    /// 2026-11-05 fixes, E9); her own Sign Out here doesn't.
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
            if isSignedIn {
                signedOutHere()
                if wholeClass?.reason == .closeArrival, !signInDeclined,
                   store.day(today, withChildren: false).method == .parentLocker {
                    awaitsSignIn = true
                }
            } else if !signInReadSinceStart {
                try? dependencies.secrets.deleteCookies(site: site)
            }
        }
        signInReadSinceStart = true
        isSignedIn = hasPassword
        savedPasswordRefused = hasPassword && refusalStands(site: site)
        if signInNeedsYou, hasPassword, let saved = try? dependencies.secrets.passwordModified(site: site),
           saved != needsYouPassword {
            signInNeedsYou = false
        }
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
