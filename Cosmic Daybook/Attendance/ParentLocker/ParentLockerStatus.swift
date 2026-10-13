import Foundation

/// Where this device stands with ParentLocker, in plain words: the one line
/// the attendance screens show ("Sent to ParentLocker 8:47 AM by Sarah · up
/// to date"), plus a line for each child it left alone and why. Never carries
/// a password, a cookie or ParentLocker's own text; that goes to `details`
/// (a Details disclosure, or the log) at most.
nonisolated struct ParentLockerStatus: Sendable, Equatable {

    enum State: Sendable, Equatable {
        /// ParentLocker isn't how attendance goes, or there's nothing to say.
        case off
        /// Signed in and watching; nothing has gone from here yet.
        case idle
        /// Nobody is signed in to ParentLocker on this device.
        case signedOut
        /// Nothing goes before arrival closes.
        case waitingForArrival
        case sending
        case upToDate
        /// Couldn't reach ParentLocker; a retry is scheduled.
        case retrying
        /// The retries ran out; the next change, a return to the app or Send Now tries again.
        case gaveUp
        /// Signed out while in the background: it signs in on the way back.
        case notSentYet
        /// ParentLocker didn't take the saved password.
        case passwordRefused
        /// ParentLocker wants something only a person can do (new terms, a reset).
        case needsYou
        case pageChanged
        /// ParentLocker answered with an error of its own.
        case refused
        /// The sign-in couldn't be read from or saved in the Keychain.
        case keychainTrouble
        /// A Debug build or a test run: it read ParentLocker and saved nothing.
        case previewed
    }

    var state: State = .off
    /// Plain lines about particular children: locked by the office, can't be
    /// cleared, not matched yet, changed by someone else.
    var problems: [String] = []
    /// When this device last finished a sync that reached ParentLocker.
    var lastSyncAt: Date?
    /// For a Details disclosure: the site's own error text or a host.
    var details: String?

    /// The state in a sentence, or nil when there's nothing to say.
    var message: String? {
        switch state {
        case .off, .idle: nil
        case .signedOut: "Sign in to ParentLocker to send attendance."
        case .waitingForArrival: "Attendance goes to ParentLocker when arrival closes."
        case .sending: "Sending to ParentLocker…"
        case .upToDate: "Up to date in ParentLocker."
        case .retrying: ParentLockerError.unreachable.errorDescription
        case .gaveUp: "Couldn't reach ParentLocker. It'll try again after the next change, or use Send Now."
        case .notSentYet: "Couldn't send to ParentLocker yet. It'll send when you open the app."
        case .passwordRefused: "ParentLocker didn't take your saved password. Sign in again."
        case .needsYou: "ParentLocker needs you to sign in again."
        case .pageChanged: ParentLockerError.pageChanged.errorDescription
        case .refused: ParentLockerError.refused(message: "").errorDescription
        case .keychainTrouble: ParentLockerKeychain.KeychainError.read(0).errorDescription
        case .previewed: "Preview only: this build reads ParentLocker but doesn't send to it."
        }
    }

    /// The screens' one line: the day's send as `AttendanceEmailLog.Send.summary`
    /// words it, then where things stand ("Sent to ParentLocker 8:47 AM by
    /// Sarah · up to date"). Nil when there's nothing to show.
    func line(sentSummary: String?) -> String? {
        guard let sentSummary, !sentSummary.isEmpty else { return message }
        switch state {
        case .off, .idle, .waitingForArrival: return sentSummary
        case .upToDate: return sentSummary + " · up to date"
        case .sending: return sentSummary + " · sending…"
        default: return message.map { sentSummary + ". " + $0 } ?? sentSummary
        }
    }

    /// Whether the line is a problem to show in the warning color.
    var isTrouble: Bool {
        switch state {
        case .retrying, .gaveUp, .notSentYet, .passwordRefused, .needsYou, .pageChanged, .refused, .keychainTrouble:
            true
        default:
            !problems.isEmpty
        }
    }
}

// MARK: - Problems in words

nonisolated extension ParentLockerStatus {

    /// The lines for what a plan left alone, children named as the class
    /// reads them ("Maya S"). Unmarked children say nothing; children not
    /// matched yet are gathered into one line.
    static func problems(
        for skipped: [ParentLockerPlanner.Skip],
        names: (UUID) -> String,
        isGuide: Bool
    ) -> [String] {
        var lines: [String] = []
        var unmatched: [String] = []
        var pageChanged = false
        for skip in skipped {
            let name = names(skip.childID)
            switch skip.reason {
            case .unmarked:
                continue
            case .unmatched, .ambiguous:
                unmatched.append(name)
            case .unknownMark:
                lines.append("\(name) has a mark this version of the app can't send. Update the app.")
            case .cantClear(let current):
                lines.append(
                    "\(name) is still \(current ?? "marked") in ParentLocker. " +
                        "ParentLocker can't clear a mark; mark her Late or Absent if that's right."
                )
            case .locked(let current):
                lines.append("The office already marked \(name)" + (current.map { " \($0)." } ?? "."))
            case .noSuchMark:
                pageChanged = true
            }
        }
        if !unmatched.isEmpty {
            let who = unmatched.count == 1
                ? "\(unmatched[0]) isn't matched to a child in ParentLocker yet."
                : "\(unmatched.count) children aren't matched in ParentLocker yet: "
                    + unmatched.joined(separator: ", ") + "."
            let fix = isGuide ? " Match them in Settings › Match Names." : " Your guide can match them in Settings."
            lines.insert(who + fix, at: 0)
        }
        if pageChanged, let text = ParentLockerError.pageChanged.errorDescription { lines.append(text) }
        return lines
    }

    /// The line for a save someone else beat: ParentLocker already held
    /// another mark, which is left as it is.
    static func conflictLine(name: String, currentMark: String?) -> String {
        "Someone else marked \(name) \(currentMark ?? "differently") in ParentLocker just now, so it was left that way."
    }
}

// MARK: - Report

/// What a sync sent, or in a preview would send, for MCP and the Debug
/// preview: per class, each change and who already matched, then what it
/// left alone. Names only as the class reads them; never a ParentLocker id.
nonisolated struct ParentLockerReport: Sendable, Equatable {

    struct Change: Sendable, Equatable {
        let name: String
        let mark: String
        /// The Notes box as sent; nil when left alone.
        let note: String?
    }

    struct ClassReport: Sendable, Equatable {
        let name: String
        let changes: [Change]
        /// Children ParentLocker already holds as they'd be sent.
        let alreadyIn: [String]
    }

    let day: Date
    /// Read only: nothing was saved.
    let wasPreview: Bool
    var classes: [ClassReport]
    var problems: [String]
    /// Classes the account lists that the app left alone, and why.
    var classesLeftAlone: [String]
    /// Children whose marks were saved.
    var savedCount: Int

    /// The report as plain text: a heading, then each class.
    var text: String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        var lines = [wasPreview
            ? "ParentLocker preview for \(date) (nothing was sent):"
            : "Sent to ParentLocker for \(date): \(savedCount == 1 ? "1 child" : "\(savedCount) children") changed."]
        if classes.isEmpty { lines.append("None of the account's classes holds this class's children.") }
        for item in classes {
            let count = item.changes.count
            let verb = wasPreview ? "send" : "change"
            lines.append("\(item.name): " + (count == 0 ? "nothing to change" : "\(count) to \(verb)"))
            for change in item.changes {
                lines.append("  \(change.name): \(change.mark)" + (change.note.map { " (Notes: \"\($0)\")" } ?? ""))
            }
            if !item.alreadyIn.isEmpty {
                lines.append("  Already in ParentLocker: " + item.alreadyIn.joined(separator: ", "))
            }
        }
        lines.append(contentsOf: classesLeftAlone.map { "Left alone: \($0)" })
        lines.append(contentsOf: problems)
        return lines.joined(separator: "\n")
    }
}
