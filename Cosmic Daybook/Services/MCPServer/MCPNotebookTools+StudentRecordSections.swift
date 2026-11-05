//
//  MCPNotebookTools+StudentRecordSections.swift
//  Cosmic Daybook
//
//  Attendance, meetings, observations and sequence standing for one child.
//  The section builders behind student_record (MCPNotebookTools+StudentRecord.swift):
//  each is the body of a tool that used to stand alone.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Attendance

    static func attendanceSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let daysBack = intArgument(arguments, "days_back", default: 30, range: 1...365)
        return describeAttendanceHistory(
            student: student, studentID: studentID, daysBack: daysBack, in: modelContext
        )
    }

    private static func describeAttendanceHistory(
        student: CDStudent, studentID: UUID, daysBack: Int,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let cutoff = AppCalendar.shared.date(
            byAdding: .day, value: -daysBack, to: AppCalendar.startOfDay(Date())
        ) ?? Date.distantPast

        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@", studentID.uuidString, cutoff as NSDate
        )
        let records = modelContext.safeFetch(request)
            .deduplicatedPerStudentDay()
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        guard !records.isEmpty else {
            return "No attendance is recorded for \(student.fullName) in the last \(daysBack) days."
        }

        var tally: [AttendanceStatus: Int] = [:]
        for record in records {
            tally[record.status, default: 0] += 1
        }
        let summary = AttendanceStatus.allCases.compactMap { status -> String? in
            guard let count = tally[status], count > 0 else { return nil }
            return "\(count) \(status.displayName.lowercased())"
        }.joined(separator: ", ")

        var lines = ["\(student.fullName), last \(daysBack) days: \(summary)."]
        let notable = records.filter { $0.status != .present && $0.status != .unmarked }
        if !notable.isEmpty {
            lines.append("Days away or late:")
            lines.append(contentsOf: notable.map { record in
                let reason = record.status == .absent && record.absenceReason != .none
                    ? " (\(record.absenceReason.displayName.lowercased()))"
                    : ""
                let note = nonEmpty(record.note).map { " — \($0)" } ?? ""
                return "- \(dayString(record.date)) \(record.status.displayName.lowercased())\(reason)\(note)"
            })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Meetings

    static func meetingsSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let limit = intArgument(arguments, "limit", default: 5, range: 1...100)
        let window = try dayWindowArgument(arguments)
        return describeMeetings(for: student, limit: limit, window: window, in: modelContext)
    }

    private static func describeMeetings(
        for student: CDStudent, limit: Int, window: DayWindow,
        in modelContext: NSManagedObjectContext
    ) -> String {
        guard let studentID = student.id else {
            return "That student record has no identifier."
        }
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        let meetings: [CDStudentMeeting] = modelContext.safeFetch(request)
            .filter { window.contains($0.date) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        guard !meetings.isEmpty else {
            return "No meetings are recorded for \(student.fullName)\(window.phrase)."
        }

        let shown: [CDStudentMeeting] = Array(meetings.prefix(limit))
        var lines: [String] = ["Meetings with \(student.fullName)\(window.phrase):"]
        for meeting in shown {
            lines.append(contentsOf: meetingLines(meeting, in: modelContext))
        }
        if meetings.count > shown.count {
            lines.append("(\(meetings.count - shown.count) older meeting(s) not shown.)")
        }
        return lines.joined(separator: "\n")
    }

    private static func meetingLines(
        _ meeting: CDStudentMeeting, in modelContext: NSManagedObjectContext
    ) -> [String] {
        let id: String = meeting.id?.uuidString ?? "unknown"
        let state: String = meeting.completed ? "" : " (not finished)"
        var lines: [String] = ["- [meeting id=\(id)] \(dayString(meeting.date))\(state)"]

        for (label, text) in [
            ("Focus", meeting.focus),
            ("Reflection", meeting.reflection),
            ("Asked for", meeting.requests),
            ("Guide notes", meeting.guideNotes)
        ] {
            if let body = nonEmpty(text) {
                lines.append("    \(label): \(body)")
            }
        }

        let reviews: [CDMeetingWorkReview] =
            (meeting.workReviews?.allObjects as? [CDMeetingWorkReview]) ?? []
        for review in reviews {
            let title: String = workTitle(forID: review.workID, in: modelContext) ?? "work"
            let note: String = nonEmpty(review.noteText).map { " — \($0)" } ?? ""
            lines.append("    Reviewed \(title)\(note)")
        }

        let notes: [CDNote] = (meeting.notes?.allObjects as? [CDNote]) ?? []
        for note in notes where !note.body.trimmed().isEmpty {
            let noteID: String = note.id?.uuidString ?? "unknown"
            lines.append("    [note id=\(noteID)] \(note.body.trimmed())")
        }
        return lines
    }

    /// A work review points at its work by id string; naming it keeps the line
    /// readable rather than printing a bare uuid.
    static func workTitle(
        forID workID: String?, in modelContext: NSManagedObjectContext
    ) -> String? {
        guard let workID, let uuid = UUID(uuidString: workID) else { return nil }
        return WorkRepository(context: modelContext).fetchWorkModel(id: uuid).map { title(of: $0) }
    }

    // MARK: - Observations

    static func observationsSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let daysBack = intArgument(arguments, "days_back", default: 30, range: 1...120)
        let window = try dayWindowArgument(arguments)
        let limit = intArgument(arguments, "limit", default: 40, range: 1...200)
        return try fetchStudentObservations(
            for: student, daysBack: daysBack, window: window, limit: limit, in: modelContext
        )
    }

    private static func fetchStudentObservations(
        for student: CDStudent, daysBack: Int, window: DayWindow, limit: Int,
        in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        // `since` replaces the rolling window; `until` alone moves it back;
        // without either the floor is the "last N days" it has always used.
        let floor = window.floor(daysBack: daysBack, now: Date())
        var clauses = [NSPredicate(format: "createdAt >= %@", floor as NSDate)]
        if let ceiling = window.endExclusive {
            clauses.append(NSPredicate(format: "createdAt < %@", ceiling as NSDate))
        }
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let matching = modelContext.safeFetch(request)
            .filter { note in
                // Classroom-wide notes aren't about this student specifically.
                switch note.scope {
                case .all: return false
                case .student(let id): return id == studentID
                case .students(let ids): return ids.contains(studentID)
                }
            }
        let shown = matching.prefix(limit)
        let scope = window.isSet ? window.phrase(daysBack: daysBack) : " (last \(daysBack) days)"
        guard !shown.isEmpty else {
            return window.isSet
                ? "No notes about \(student.fullName)\(window.phrase(daysBack: daysBack))."
                : "No notes about \(student.fullName) in the last \(daysBack) days."
        }

        let lines = shown.map { note -> String in
            let tags = note.tagsArray.isEmpty ? "" : " [\(note.tagsArray.joined(separator: ", "))]"
            let id = note.id?.uuidString ?? "unknown"
            return "- [note id=\(id)] \(dayString(note.createdAt))\(tags): \(note.body)"
        }
        let held = matching.count > shown.count
            ? " (showing \(shown.count) of \(matching.count); raise limit or pass since/until for the rest)"
            : ""
        return "Notes about \(student.fullName)\(scope)\(held):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Sequence Standing

    static func tracksSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) -> String {
        let includeFinished = arguments["include_inactive"]?.boolValue ?? false
        return describeStandings(for: student, includeFinished: includeFinished, in: modelContext)
    }

    /// One line per sequence the child has started, from her presentation
    /// record (`SequenceStandingLoader`): the ones in progress, and with
    /// `includeFinished` the ones she has mastered every lesson of.
    private static func describeStandings(
        for student: CDStudent, includeFinished: Bool, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let studentID = student.id else {
            return "That student record has no identifier."
        }
        let standings = SequenceStandingLoader.standings(forStudentID: studentID.uuidString, in: modelContext)
            .filter { $0.isInProgress || (includeFinished && $0.isFinished) }
        guard !standings.isEmpty else {
            return "\(student.fullName) has not started any lesson sequences."
        }
        let lines: [String] = standings.map(standingLine)
        return (["\(student.fullName)'s sequences:"] + lines).joined(separator: "\n")
    }

    private static func standingLine(_ standing: SequenceStanding) -> String {
        var details: [String] = ["\(standing.masteredCount)/\(standing.total) lessons mastered"]
        if standing.isFinished {
            details.append("complete")
        } else if let next = standing.nextLesson {
            details.append("next: \(next.name)")
        }
        return "- [sequence: \(standing.title)] \(details.joined(separator: "; "))"
    }
}
