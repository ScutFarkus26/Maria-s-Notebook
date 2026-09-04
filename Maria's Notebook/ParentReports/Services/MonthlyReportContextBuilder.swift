// MonthlyReportContextBuilder.swift
// Gathers one student's recorded month into typed, citable evidence for a
// monthly parent report. Every item restates something the guide recorded —
// nothing here is inferred.

import Foundation
import CoreData

/// One recorded fact backing a report narrative, citable as "kind:uuid"
/// (matching the `[kind id=<uuid>]` convention in NotebookTools).
struct MonthlyReportEvidenceItem: Sendable, Identifiable, Equatable {
    let ref: String
    let date: Date
    let phrase: String

    var id: String { ref }
}

/// Attendance counts for the month, from guide-marked records only.
struct MonthlyReportAttendanceSummary: Sendable, Equatable {
    let daysPresent: Int
    let daysAbsent: Int
    let tardies: Int

    var markedDays: Int { daysPresent + daysAbsent }
}

/// Everything recorded for one (student, month), grouped for drafting.
struct MonthlyReportContext: Sendable {
    let studentName: String
    let level: CDStudent.Level
    let month: ReportMonth
    let lessonsPresented: [MonthlyReportEvidenceItem]
    let workEvidence: [MonthlyReportEvidenceItem]
    let observations: [MonthlyReportEvidenceItem]
    let contributions: [MonthlyReportEvidenceItem]
    let studentReflections: [MonthlyReportEvidenceItem]
    let attendance: MonthlyReportAttendanceSummary?

    var allItems: [MonthlyReportEvidenceItem] {
        lessonsPresented + workEvidence + observations + contributions + studentReflections
    }

    var allRefs: [String] { allItems.map(\.ref) }

    var isEmpty: Bool { allItems.isEmpty }
}

/// Builds a `MonthlyReportContext` from Core Data. Every fetch is scoped to
/// the one student; the notes path reuses `ReportGeneratorService`'s
/// includeInReport + scope privacy filter.
struct MonthlyReportContextBuilder {
    let context: NSManagedObjectContext
    let reportService: ReportGeneratorService
    var calendar: Calendar = AppCalendar.shared

    /// Half-open month membership: `DateInterval.contains` includes the end
    /// bound, which would leak a midnight-boundary record into the prior month.
    private func inMonth(_ date: Date, _ interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    func buildContext(
        for student: CDStudent,
        month: ReportMonth,
        includeStudentReflection: Bool
    ) -> MonthlyReportContext {
        let studentID = student.id?.uuidString ?? ""
        let interval = month.dateInterval(calendar: calendar)

        let presentationItems = presentationEvidence(studentID: studentID, interval: interval)
        let assignmentItems = assignmentEvidence(
            studentID: studentID,
            interval: interval,
            excludingLessonIDs: presentationItems.coveredLessonIDs
        )

        let reflections: [MonthlyReportEvidenceItem]
        if includeStudentReflection && student.level == .adolescent {
            reflections = reflectionEvidence(studentID: studentID, interval: interval)
        } else {
            reflections = []
        }

        return MonthlyReportContext(
            studentName: StudentFormatter.displayName(for: student),
            level: student.level,
            month: month,
            lessonsPresented: (presentationItems.items + assignmentItems).sorted { $0.date < $1.date },
            workEvidence: workEvidence(studentID: studentID, interval: interval),
            observations: observationEvidence(student: student, month: month),
            contributions: student.level == .adolescent
                ? contributionEvidence(studentID: studentID, interval: interval)
                : [],
            studentReflections: reflections,
            attendance: attendanceSummary(studentID: studentID, interval: interval)
        )
    }

    // MARK: - Lessons (presentations + guide-recorded transitions)

    private func presentationEvidence(
        studentID: String,
        interval: DateInterval
    ) -> (items: [MonthlyReportEvidenceItem], coveredLessonIDs: Set<String>) {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@", studentID)
        let presentations = context.safeFetch(request)

        let lessonNames = lessonNameIndex(for: presentations.map(\.lessonID))
        var items: [MonthlyReportEvidenceItem] = []
        var covered: Set<String> = []

        for presentation in presentations {
            guard let id = presentation.id?.uuidString else { continue }
            let lessonName = lessonNames[presentation.lessonID] ?? "a lesson"

            // Filter on transition dates, not current state, so the month
            // only reports what the guide recorded during it.
            if let presentedAt = presentation.presentedAt, inMonth(presentedAt, interval) {
                covered.insert(presentation.lessonID)
                items.append(MonthlyReportEvidenceItem(
                    ref: "presentation:\(id)",
                    date: presentedAt,
                    phrase: "Received the lesson “\(lessonName)”"
                ))
            }

            if let masteredAt = presentation.masteredAt, inMonth(masteredAt, interval) {
                items.append(MonthlyReportEvidenceItem(
                    ref: "presentation:\(id)#proficient",
                    date: masteredAt,
                    phrase: "The guide recorded proficiency with “\(lessonName)”"
                ))
            }

            if let updatedAt = presentation.followUpUpdatedAt,
               inMonth(updatedAt, interval),
               !presentation.followUpEvidence.isEmpty {
                let observed = presentation.followUpEvidence
                    .map(\.title)
                    .sorted()
                    .joined(separator: "; ")
                items.append(MonthlyReportEvidenceItem(
                    ref: "presentation:\(id)#evidence",
                    date: updatedAt,
                    phrase: "With “\(lessonName)”: \(observed)"
                ))
            }
        }
        return (items, covered)
    }

    /// Group lessons presented in-month that have no per-student presentation
    /// row — the assignment's title snapshot is the only record.
    private func assignmentEvidence(
        studentID: String,
        interval: DateInterval,
        excludingLessonIDs: Set<String>
    ) -> [MonthlyReportEvidenceItem] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "presentedAt >= %@ AND presentedAt < %@",
            interval.start as NSDate, interval.end as NSDate
        )
        return context.safeFetch(request).compactMap { assignment in
            guard let id = assignment.id?.uuidString,
                  let presentedAt = assignment.presentedAt,
                  assignment.studentIDs.contains(studentID),
                  !excludingLessonIDs.contains(assignment.lessonID) else { return nil }
            let title = assignment.lessonTitleSnapshot ?? "a lesson"
            return MonthlyReportEvidenceItem(
                ref: "assignment:\(id)",
                date: presentedAt,
                phrase: "Received the lesson “\(title)”"
            )
        }
    }

    private func lessonNameIndex(for lessonIDs: [String]) -> [String: String] {
        let uuids = lessonIDs.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        var index: [String: String] = [:]
        for lesson in context.safeFetch(request) {
            guard let id = lesson.id?.uuidString else { continue }
            index[id] = lesson.name
        }
        return index
    }

    // MARK: - Work

    private func workEvidence(studentID: String, interval: DateInterval) -> [MonthlyReportEvidenceItem] {
        var items: [MonthlyReportEvidenceItem] = []

        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(
            format: "studentID == %@ AND completedAt >= %@ AND completedAt < %@",
            studentID, interval.start as NSDate, interval.end as NSDate
        )
        for work in context.safeFetch(workRequest) {
            guard let id = work.id?.uuidString, let completedAt = work.completedAt else { continue }
            items.append(MonthlyReportEvidenceItem(
                ref: "work:\(id)",
                date: completedAt,
                phrase: "Completed “\(work.title)”"
            ))
        }

        let practiceRequest = CDFetchRequest(CDPracticeSession.self)
        practiceRequest.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND madeBreakthrough == YES",
            interval.start as NSDate, interval.end as NSDate
        )
        for session in context.safeFetch(practiceRequest) {
            guard let id = session.id?.uuidString,
                  let date = session.date,
                  session.studentIDsArray.contains(studentID) else { continue }
            items.append(MonthlyReportEvidenceItem(
                ref: "practice:\(id)",
                date: date,
                phrase: "Made a breakthrough during independent practice"
            ))
        }

        return items.sorted { $0.date < $1.date }
    }

    // MARK: - Observations (includeInReport notes, privacy-scoped)

    private func observationEvidence(student: CDStudent, month: ReportMonth) -> [MonthlyReportEvidenceItem] {
        let notes = reportService.fetchReportNotes(
            for: student,
            dateRange: month.closedRange(calendar: calendar),
            context: context
        )
        return notes.compactMap { note in
            guard let id = note.id?.uuidString, let createdAt = note.createdAt else { return nil }
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return MonthlyReportEvidenceItem(ref: "note:\(id)", date: createdAt, phrase: body)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Adolescent contributions (valorization: real, meaningful work)

    private func contributionEvidence(studentID: String, interval: DateInterval) -> [MonthlyReportEvidenceItem] {
        var items: [MonthlyReportEvidenceItem] = []

        let goingOutRequest = CDFetchRequest(CDGoingOut.self)
        for trip in context.safeFetch(goingOutRequest) {
            guard let id = trip.id?.uuidString,
                  let date = trip.actualDate ?? trip.proposedDate,
                  inMonth(date, interval),
                  trip.studentIDsArray.contains(studentID) else { continue }
            let destination = trip.destination.isEmpty ? trip.title : trip.destination
            items.append(MonthlyReportEvidenceItem(
                ref: "goingOut:\(id)",
                date: date,
                phrase: "Went out to \(destination)"
            ))
        }

        let jobRequest = CDFetchRequest(CDJobAssignment.self)
        jobRequest.predicate = NSPredicate(
            format: "studentID == %@ AND weekStartDate >= %@ AND weekStartDate < %@",
            studentID, interval.start as NSDate, interval.end as NSDate
        )
        for assignment in context.safeFetch(jobRequest) {
            guard let id = assignment.id?.uuidString,
                  let weekStart = assignment.weekStartDate,
                  let jobName = assignment.job?.name, !jobName.isEmpty else { continue }
            items.append(MonthlyReportEvidenceItem(
                ref: "jobAssignment:\(id)",
                date: weekStart,
                phrase: "Held the classroom responsibility “\(jobName)”"
            ))
        }

        return items.sorted { $0.date < $1.date }
    }

    // MARK: - Student reflections (adolescent, per-report opt-in)

    private func reflectionEvidence(studentID: String, interval: DateInterval) -> [MonthlyReportEvidenceItem] {
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@ AND date < %@",
            studentID, interval.start as NSDate, interval.end as NSDate
        )
        return context.safeFetch(request).compactMap { meeting in
            guard let id = meeting.id?.uuidString, let date = meeting.date else { return nil }
            let reflection = meeting.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reflection.isEmpty else { return nil }
            return MonthlyReportEvidenceItem(
                ref: "meeting:\(id)",
                date: date,
                phrase: "In their own words: “\(reflection)”"
            )
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Attendance

    private func attendanceSummary(studentID: String, interval: DateInterval) -> MonthlyReportAttendanceSummary? {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@ AND date < %@",
            studentID, interval.start as NSDate, interval.end as NSDate
        )
        let records = context.safeFetch(request)
        guard !records.isEmpty else { return nil }

        var present = 0
        var absent = 0
        var tardy = 0
        for record in records {
            switch AttendanceStatus(rawValue: record.statusRaw) {
            case .present:
                present += 1
            case .tardy, .leftEarly:
                present += 1
                tardy += 1
            case .absent:
                absent += 1
            case .unmarked, .none:
                continue
            }
        }
        guard present + absent > 0 else { return nil }
        return MonthlyReportAttendanceSummary(daysPresent: present, daysAbsent: absent, tardies: tardy)
    }
}
