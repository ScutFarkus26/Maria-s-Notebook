//
//  AttendanceIntents.swift
//  Cosmic Daybook
//
//  "Mark Maya here", "Mark Maya late", "Mark Maya absent" and "Undo that",
//  by voice or from Shortcuts, without opening the app. Every mark goes
//  through `SiriAttendance`, the same `CDAttendanceStore` path a grid tap
//  takes.
//
//  Shared with Daybook Assistant, which compiles this file by path. Here and
//  late work on a locked phone, so a guide greeting children at the door can
//  mark them hands-free; absent needs the phone unlocked and a confirmation.
//  Undo needs the phone unlocked too: it can put back an absent mark or the
//  Assistant's Close Arrival, which both needed unlocking to make.
//

import AppIntents

// MARK: - Here

struct MarkHereIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Student Here"
    static let description = IntentDescription(
        "Mark a student present today, or late once arrival has closed.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$student) here today")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await SiriAttendance()
        let child = try session.student(for: student)
        let name = session.spokenName(for: child)
        try await SiriAttendance.confirmIfNoSchool(session, marking: name, for: self)

        let (previous, status) = try await session.markHere(child)
        if previous == status {
            return .result(dialog: IntentDialog(
                full: "\(name) was already marked \(status.spokenWord).",
                supporting: "Already \(status.spokenWord)"
            ))
        }
        if status == .tardy {
            return .result(dialog: IntentDialog(
                full: "Arrival has closed, so \(name) is marked late.",
                supporting: "Late"
            ))
        }
        return .result(dialog: IntentDialog(full: "\(name) is marked present.", supporting: "Present"))
    }
}

// MARK: - Late

struct MarkLateIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Student Late"
    static let description = IntentDescription(
        "Mark a student late today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$student) late today")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await SiriAttendance()
        let child = try session.student(for: student)
        let name = session.spokenName(for: child)
        try await SiriAttendance.confirmIfNoSchool(session, marking: name, for: self)

        let previous = try await session.mark(child, as: .tardy)
        if previous == .tardy {
            return .result(dialog: IntentDialog(full: "\(name) was already marked late.", supporting: "Already late"))
        }
        return .result(dialog: IntentDialog(full: "\(name) is marked late.", supporting: "Late"))
    }
}

// MARK: - Absent

struct MarkAbsentIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Student Absent"
    static let description = IntentDescription(
        "Mark a student absent today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Student")
    var student: StudentEntity

    @Parameter(title: "Reason")
    var reason: SiriAbsenceReason?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$student) absent today") {
            \.$reason
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await SiriAttendance()
        let child = try session.student(for: student)
        let name = session.spokenName(for: child)
        if session.isSchoolDay {
            try await requestConfirmation(dialog: "Mark \(name) absent today?")
        } else {
            try await SiriAttendance.confirmIfNoSchool(session, marking: name, for: self)
        }

        let previous = try await session.mark(child, as: .absent, reason: reason?.reason)
        if let reason, previous == .absent {
            return .result(dialog: IntentDialog(
                full: "\(name) is marked absent: \(reason.reason.displayName.lowercased()).", supporting: "Absent"
            ))
        }
        if previous == .absent {
            return .result(dialog: IntentDialog(
                full: "\(name) was already marked absent.", supporting: "Already absent"
            ))
        }
        return .result(dialog: IntentDialog(full: "\(name) is marked absent.", supporting: "Absent"))
    }
}

// MARK: - Undo

struct UndoAttendanceIntent: AppIntent {
    // App Store Connect rejects an intent title, description or phrase that contains "Siri" (90626).
    static let title: LocalizedStringResource = "Undo Last Attendance Mark"
    static let description = IntentDescription(
        "Put back the last attendance change made by voice or a shortcut today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await SiriAttendance().undoLast()
        return .result(dialog: IntentDialog(full: "\(dialog)", supporting: "Undone"))
    }
}

/// Why a child is away, as Siri and Shortcuts offer it.
enum SiriAbsenceReason: String, AppEnum {
    case sick, vacation, appointment, family, other

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Absence Reason")
    }

    static let caseDisplayRepresentations: [SiriAbsenceReason: DisplayRepresentation] = [
        .sick: "Sick", .vacation: "Vacation", .appointment: "Appointment", .family: "Family", .other: "Other"
    ]

    var reason: AbsenceReason { AbsenceReason(rawValue: rawValue) ?? .other }
}
