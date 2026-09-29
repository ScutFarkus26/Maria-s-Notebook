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
        "Mark a student present today, or tardy once arrival has closed in Daybook Assistant.",
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
        let session = try SiriAttendance()
        let child = try session.student(for: student)
        try await SiriAttendance.confirmIfNoSchool(session, marking: child.fullName, for: self)

        let name = child.fullName
        var status = SiriHost.statusForHere(on: session.today)
        // After arrival closes, a child already marked present stays present,
        // as a tap on the grid leaves them.
        if status == .tardy, try session.status(of: child) == .present {
            status = .present
        }
        let previous = try await session.mark(child, as: status)
        if previous == status {
            return .result(dialog: IntentDialog(
                full: "\(name) was already marked \(status.displayName.lowercased()).",
                supporting: "Already \(status.displayName.lowercased())"
            ))
        }
        if status == .tardy {
            return .result(dialog: IntentDialog(
                full: "Arrival has closed, so \(name) is marked tardy.",
                supporting: "Tardy"
            ))
        }
        return .result(dialog: IntentDialog(full: "\(name) is marked present.", supporting: "Present"))
    }
}

// MARK: - Late

struct MarkLateIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Student Late"
    static let description = IntentDescription(
        "Mark a student tardy today.",
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
        let session = try SiriAttendance()
        let child = try session.student(for: student)
        try await SiriAttendance.confirmIfNoSchool(session, marking: child.fullName, for: self)

        let previous = try await session.mark(child, as: .tardy)
        let name = child.fullName
        if previous == .tardy {
            return .result(dialog: IntentDialog(full: "\(name) was already marked tardy.", supporting: "Already tardy"))
        }
        return .result(dialog: IntentDialog(full: "\(name) is marked tardy.", supporting: "Tardy"))
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
        let session = try SiriAttendance()
        let child = try session.student(for: student)
        let name = child.fullName
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
    static let title: LocalizedStringResource = "Undo Last Attendance Mark"
    static let description = IntentDescription(
        "Put back the last attendance change made with Siri today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await SiriAttendance().undoLast()
        return .result(dialog: IntentDialog(full: "Undid \(summary).", supporting: "Undone"))
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
