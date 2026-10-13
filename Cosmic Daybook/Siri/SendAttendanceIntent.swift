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
        let reply = Self.reply(to: await sync.send(day: Date(), preview: false))
        return .result(dialog: "\(reply)")
    }

    /// What the action says: what went, that nothing needed to, or why it
    /// didn't go, in plain words (the sync words its failures).
    static func reply(to result: Result<ParentLockerReport, ParentLockerSendFailure>) -> String {
        switch result {
        case .success(let report) where report.wasPreview:
            return "This test copy of the app only previews. Nothing was sent to ParentLocker."
        case .success(let report) where report.savedCount == 0:
            return "ParentLocker already has today's attendance." + firstProblem(report)
        case .success(let report):
            let children = report.savedCount == 1 ? "1 child" : "\(report.savedCount) children"
            return "Sent today's attendance to ParentLocker: \(children) updated." + firstProblem(report)
        case .failure(let failure):
            return failure.message
        }
    }

    /// The first child it left alone, and why ("The office already marked Maya S Absent.").
    private static func firstProblem(_ report: ParentLockerReport) -> String {
        report.problems.first.map { " " + $0 } ?? ""
    }
}
