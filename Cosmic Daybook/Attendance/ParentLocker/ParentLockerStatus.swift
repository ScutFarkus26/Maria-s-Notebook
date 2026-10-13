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
        /// Everyone's marked but arrival never closed, so there's no Close
        /// Arrival to tap: Send to ParentLocker sends the day.
        case readyToSend
        /// Every class ParentLocker lists for today says it isn't expecting
        /// attendance: nothing goes, and nothing is due.
        case notExpected
        /// A send asked for while this device needs a sign-in: today's waits
        /// for one, another day's didn't go. Only a Send Now's answer says it.
        case waitingForSignIn
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

    /// What every screen, Siri and the Shortcut say on a day ParentLocker
    /// isn't expecting the class's attendance.
    static let notExpectedLine = "ParentLocker isn't expecting attendance today."

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
        case .signedOut: ParentLockerSyncStop.signedOut.message
        case .waitingForArrival: "Attendance goes to ParentLocker when arrival closes."
        case .readyToSend: "Everyone's marked. Send it to ParentLocker."
        case .notExpected: Self.notExpectedLine
        case .waitingForSignIn: ParentLockerSyncStop.signInToSend
        case .sending: "Sending to ParentLocker…"
        case .upToDate: "Up to date in ParentLocker."
        case .retrying: ParentLockerError.unreachable.errorDescription
        case .gaveUp: "Couldn't reach ParentLocker. It'll try again after the next change, or use Send Now."
        case .notSentYet: ParentLockerSyncStop.notSentYet.message
        case .passwordRefused: ParentLockerSyncStop.passwordRefused.message
        case .needsYou: ParentLockerSyncStop.needsYou.message
        case .pageChanged: ParentLockerError.pageChanged.errorDescription
        case .refused: ParentLockerError.refused(message: "").errorDescription
        case .keychainTrouble: ParentLockerSyncStop.keychain.message
        case .previewed: "This test copy of the app only previews. Nothing was sent to ParentLocker."
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

// MARK: - Why a run stopped

/// Why a run stopped before reaching ParentLocker, each with its sentence for
/// the screens (the line, the sign-in sheet, Match Names).
nonisolated enum ParentLockerSyncStop: Error, Equatable, LocalizedError {
    /// No password saved for the site: never signed in here, or signed out.
    case signedOut
    /// Signed out while in the background, where the web view can't sign in.
    case notSentYet
    /// ParentLocker didn't take the saved password.
    case passwordRefused
    /// ParentLocker wants something only a person can do.
    case needsYou
    /// The Keychain wouldn't read or save the sign-in.
    case keychain

    var message: String {
        switch self {
        case .signedOut: "Sign in to ParentLocker to send attendance."
        case .notSentYet: "Couldn't send to ParentLocker yet. It'll send when you open the app."
        case .passwordRefused: "ParentLocker didn't take your saved password. Sign in again."
        case .needsYou: "ParentLocker needs you to sign in again."
        case .keychain:
            "Couldn't use your saved ParentLocker sign-in on this device. Restart the device and try again."
        }
    }

    var errorDescription: String? { message }

    /// What a send asked for while this device needs a sign-in answers.
    static let signInToSend = "Sign in to ParentLocker to send."
}

nonisolated extension ParentLockerStatus {
    /// What a run that didn't get through leaves on the line.
    static func failure(for error: Error, lastSyncAt: Date?) -> ParentLockerStatus {
        let state: State
        var details: String?
        switch error {
        case ParentLockerError.unreachable: state = .retrying
        case ParentLockerSyncStop.signedOut: state = .signedOut
        case ParentLockerSyncStop.notSentYet: state = .notSentYet
        case ParentLockerSyncStop.passwordRefused: state = .passwordRefused
        case ParentLockerSyncStop.needsYou: state = .needsYou
        case ParentLockerSyncStop.keychain: state = .keychainTrouble
        case ParentLockerError.refused(let message):
            state = .refused
            details = message
        default:
            // The page changed, a redirect off the site, or a sign-in the
            // requests still can't use: nothing to retry until someone looks.
            state = .pageChanged
            details = (error as? ParentLockerError)?.details
        }
        return ParentLockerStatus(state: state, lastSyncAt: lastSyncAt, details: details)
    }
}

/// A send or preview that didn't happen, in plain words, for the screen or
/// MCP that asked; `details` (the site's own text, a host) for a Details
/// disclosure at most.
nonisolated struct ParentLockerSendFailure: Error, Equatable, Sendable {
    let message: String
    var details: String?
}

// MARK: - Problems in words

nonisolated extension ParentLockerStatus {

    /// The lines for what a plan left alone, children named as the class
    /// reads them ("Maya S"). Unmarked children and those the guide left out
    /// ("Not matched") say nothing; children not matched yet are gathered
    /// into one line.
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
            case .unmarked, .leftOut:
                continue
            case .unmatched, .ambiguous:
                unmatched.append(name)
            case .unknownMark:
                lines.append("\(name) has a mark this version of the app can't send. Update the app.")
            case .cantClear(let current):
                lines.append(
                    "\(name) is still \(current ?? "marked") in ParentLocker, which can't remove a mark. " +
                        "If that's wrong, give \(name) the right mark here."
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
            let fix = isGuide
                ? " Match them in Settings › Messages › Match Names."
                : " Your guide can match them in Settings."
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
    /// Classes the account lists that the app left alone, each a sentence
    /// saying why ("Skipped Art: it doesn't take daily attendance.").
    var classesLeftAlone: [String]
    /// Children whose marks were saved.
    var savedCount: Int
    /// The children on the roll with no mark yet ("Maya S"), not sent.
    var unmarked: [String] = []
    /// The day isn't recorded as sent: a send asked for with children still
    /// unmarked counts only once everyone is.
    var waitsForMarks = false
    /// ParentLocker expects no attendance from any of the classes that day.
    var notExpected = false

    /// The report as plain text: a heading, then each class.
    var text: String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        var lines = [wasPreview
            ? "ParentLocker preview for \(date) (nothing was sent):"
            : "Sent to ParentLocker for \(date): \(savedCount == 1 ? "1 child" : "\(savedCount) children") changed."]
        if notExpected {
            lines.append("ParentLocker isn't expecting attendance from your classes that day.")
        } else if classes.isEmpty {
            lines.append("None of your ParentLocker classes has any of these children.")
        }
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
        if !unmarked.isEmpty {
            lines.append("Not marked yet, so not sent: " + unmarked.joined(separator: ", ") + ".")
        }
        if waitsForMarks {
            lines.append("The day isn't recorded as sent until everyone is marked and it's sent again.")
        }
        lines.append(contentsOf: classesLeftAlone)
        lines.append(contentsOf: problems)
        return lines.joined(separator: "\n")
    }
}
