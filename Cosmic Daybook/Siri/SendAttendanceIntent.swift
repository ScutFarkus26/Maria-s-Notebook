//
//  SendAttendanceIntent.swift
//  Cosmic Daybook
//
//  "Send Attendance to School", a Shortcuts action (plan "ParentLocker
//  attendance", Phase 3): today's whole class to the school's ParentLocker
//  site, as Send Now on the attendance screen does. No Siri phrase: the
//  notebook is at Apple's 10 App Shortcuts, and Danny asked for none. Notebook
//  only (the Daybook Assistant's Close Arrival sends by itself).
//

import AppIntents

struct SendAttendanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Attendance to School"
    static let description = IntentDescription(
        "Send today's attendance to the school's ParentLocker site. Only marks that differ there are changed.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stack: CoreDataStack
        do {
            stack = try await SiriAttendance.openStack()
        } catch {
            return .result(dialog: "\(SiriHost.cannotOpenMessage)")
        }
        guard let sync = AppBootstrapper.startParentLockerSync(on: stack) else {
            return .result(dialog: "Couldn't send to ParentLocker. Open the app and try again.")
        }
        let day = Date()
        // Children still unmarked: ask first, as the attendance screen does
        // (bug hunt 2026-10-13 afternoon, M4). A "no" stops the action.
        if let question = Self.unmarkedQuestion(count: sync.unmarkedNames(on: day).count) {
            try await requestConfirmation(actionName: .send, dialog: "\(question)")
        }
        let reply = Self.reply(to: await sync.send(day: day, preview: false))
        return .result(dialog: "\(reply)")
    }

    /// What the action asks with `count` children unmarked ("3 children
    /// aren't marked yet. Send the rest?"), or nil when everyone is.
    static func unmarkedQuestion(count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 child isn't marked yet. Send the rest?"
        default: "\(count) children aren't marked yet. Send the rest?"
        }
    }

    /// What the action says: what went, that nothing needed to, or why it
    /// didn't go, in plain words (the sync words its failures). After a send
    /// with children unmarked, who they are, and that the day isn't recorded
    /// as sent (review of the afternoon fixes).
    static func reply(to result: Result<ParentLockerReport, ParentLockerSendFailure>) -> String {
        switch result {
        case .success(let report) where report.wasPreview:
            return "This test copy of the app only previews. Nothing was sent to ParentLocker."
        case .success(let report) where report.notExpected:
            return ParentLockerStatus.notExpectedLine
        case .success(let report) where report.savedCount == 0:
            let already = report.waitsForMarks
                ? "ParentLocker already has everyone who's marked." : "ParentLocker already has today's attendance."
            return already + unmarkedLine(report) + firstProblem(report)
        case .success(let report):
            let children = report.savedCount == 1 ? "1 child" : "\(report.savedCount) children"
            return "Sent today's attendance to ParentLocker: \(children) updated."
                + unmarkedLine(report) + firstProblem(report)
        case .failure(let failure):
            return failure.message
        }
    }

    /// The children a send left out for want of a mark: up to three by name,
    /// more as a count ("Bea M isn't marked yet, so today isn't recorded as
    /// sent."). Nothing when the day counts as sent.
    private static func unmarkedLine(_ report: ParentLockerReport) -> String {
        guard report.waitsForMarks, !report.unmarked.isEmpty else { return "" }
        let count = report.unmarked.count
        let who = count <= 3 ? report.unmarked.formatted(.list(type: .and)) : "\(count) children"
        return " \(who) \(count == 1 ? "isn't" : "aren't") marked yet, so today isn't recorded as sent."
    }

    /// The first child it left alone, and why ("The office already marked Maya S Absent.").
    private static func firstProblem(_ report: ParentLockerReport) -> String {
        report.problems.first.map { " " + $0 } ?? ""
    }
}
