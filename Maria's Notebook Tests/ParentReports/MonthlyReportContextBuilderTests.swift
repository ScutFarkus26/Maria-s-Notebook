// MonthlyReportContextBuilderTests.swift
// The context builder decides what a family can be told about a month.
// These tests pin down the privacy boundary (one child's report never sees
// another child's records), the month window, and the reflection opt-in.

import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Monthly Report Context Builder")
@MainActor
final class MonthlyReportContextBuilderTests {

    private let month = ReportMonth(year: 2026, month: 9)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func makeBuilder(_ context: NSManagedObjectContext) -> MonthlyReportContextBuilder {
        MonthlyReportContextBuilder(
            context: context,
            reportService: ReportGeneratorService(),
            calendar: calendar
        )
    }

    @discardableResult
    private func seedLesson(in context: NSManagedObjectContext, name: String) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.id = UUID()
        lesson.name = name
        return lesson
    }

    @discardableResult
    private func seedPresentation(
        in context: NSManagedObjectContext,
        studentID: String,
        lessonID: String,
        presentedAt: Date? = nil,
        masteredAt: Date? = nil
    ) -> CDLessonPresentation {
        let presentation = CDLessonPresentation(context: context)
        presentation.id = UUID()
        presentation.studentID = studentID
        presentation.lessonID = lessonID
        presentation.stateRaw = LessonPresentationState.presented.rawValue
        presentation.presentedAt = presentedAt
        presentation.masteredAt = masteredAt
        return presentation
    }

    @Test("Only in-month records appear, keyed to transition dates")
    func monthWindowFiltersOnTransitionDates() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ezra", lastName: "Bloom", level: .upper)
        let studentID = try #require(student.id).uuidString
        let lesson = seedLesson(in: ctx, name: "Checkerboard")
        let lessonID = try #require(lesson.id).uuidString

        // Presented in August, proficiency recorded in September: only the
        // September transition may appear in the September report.
        seedPresentation(
            in: ctx,
            studentID: studentID,
            lessonID: lessonID,
            presentedAt: date(2026, 8, 20),
            masteredAt: date(2026, 9, 10)
        )

        let inMonthWork = CDWorkModel(context: ctx)
        inMonthWork.id = UUID()
        inMonthWork.studentID = studentID
        inMonthWork.title = "Checkerboard follow-up"
        inMonthWork.completedAt = date(2026, 9, 15)

        let outOfMonthWork = CDWorkModel(context: ctx)
        outOfMonthWork.id = UUID()
        outOfMonthWork.studentID = studentID
        outOfMonthWork.title = "October work"
        outOfMonthWork.completedAt = date(2026, 10, 1, hour: 0)
        #expect(CoreDataTestHelpers.save(ctx))

        let context = makeBuilder(ctx).buildContext(for: student, month: month, includeStudentReflection: false)

        #expect(context.lessonsPresented.count == 1)
        #expect(context.lessonsPresented.first?.phrase.contains("proficiency") == true)
        #expect(context.lessonsPresented.first?.phrase.contains("Checkerboard") == true)
        #expect(context.workEvidence.map(\.phrase) == ["Completed “Checkerboard follow-up”"])
    }

    @Test("One student's context never references another student's records")
    func privacyIsolation() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let maya = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Maya", lastName: "Stone", level: .upper)
        let rina = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Rina", lastName: "Ash", level: .adolescent)
        let rinaID = try #require(rina.id)
        let lesson = seedLesson(in: ctx, name: "Great River")
        let lessonID = try #require(lesson.id).uuidString

        seedPresentation(in: ctx, studentID: rinaID.uuidString, lessonID: lessonID, presentedAt: date(2026, 9, 3))

        let rinaNote = CDNote(context: ctx)
        rinaNote.body = "Rina led the composting project"
        rinaNote.includeInReport = true
        rinaNote.createdAt = date(2026, 9, 4)
        rinaNote.scope = .student(rinaID)

        let rinaMeeting = CDStudentMeeting(context: ctx)
        rinaMeeting.id = UUID()
        rinaMeeting.studentID = rinaID.uuidString
        rinaMeeting.date = date(2026, 9, 5)
        rinaMeeting.reflection = "I am proud of the farm stand"
        #expect(CoreDataTestHelpers.save(ctx))

        let builder = makeBuilder(ctx)
        let mayaContext = builder.buildContext(for: maya, month: month, includeStudentReflection: true)

        #expect(mayaContext.isEmpty)
        let allPhrases = mayaContext.allItems.map(\.phrase).joined()
        #expect(!allPhrases.contains("Rina"))

        // And Rina's own context does see her records.
        let rinaContext = builder.buildContext(for: rina, month: month, includeStudentReflection: false)
        #expect(rinaContext.lessonsPresented.count == 1)
        #expect(rinaContext.observations.count == 1)
    }

    @Test("Notes not flagged includeInReport never appear")
    func unflaggedNotesExcluded() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Tamar", lastName: "Reed", level: .upper)
        let studentID = try #require(student.id)

        let privateNote = CDNote(context: ctx)
        privateNote.body = "Private working note"
        privateNote.includeInReport = false
        privateNote.createdAt = date(2026, 9, 8)
        privateNote.scope = .student(studentID)
        #expect(CoreDataTestHelpers.save(ctx))

        let context = makeBuilder(ctx).buildContext(for: student, month: month, includeStudentReflection: false)
        #expect(context.observations.isEmpty)
    }

    @Test("Student reflection is opt-in and adolescent-only")
    func reflectionGating() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let adolescent = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Rina", lastName: "Ash", level: .adolescent)
        let upperEl = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Eli", lastName: "Brooks", level: .upper)
        let adolescentID = try #require(adolescent.id).uuidString
        let upperID = try #require(upperEl.id).uuidString

        for (studentID, text) in [(adolescentID, "The bakery was hard but worth it"), (upperID, "Upper el reflection")] {
            let meeting = CDStudentMeeting(context: ctx)
            meeting.id = UUID()
            meeting.studentID = studentID
            meeting.date = date(2026, 9, 12)
            meeting.reflection = text
        }
        #expect(CoreDataTestHelpers.save(ctx))

        let builder = makeBuilder(ctx)

        // Off by default.
        let defaultContext = builder.buildContext(for: adolescent, month: month, includeStudentReflection: false)
        #expect(defaultContext.studentReflections.isEmpty)

        // On for the adolescent.
        let optedIn = builder.buildContext(for: adolescent, month: month, includeStudentReflection: true)
        #expect(optedIn.studentReflections.count == 1)
        #expect(optedIn.studentReflections.first?.phrase.contains("bakery") == true)

        // Never for elementary, even when asked.
        let upperContext = builder.buildContext(for: upperEl, month: month, includeStudentReflection: true)
        #expect(upperContext.studentReflections.isEmpty)
    }

    @Test("Attendance summary counts only marked days")
    func attendanceSummary() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Noah", lastName: "Linden", level: .upper)
        let studentID = try #require(student.id).uuidString

        let statuses: [(Int, String)] = [(1, "present"), (2, "present"), (3, "tardy"), (4, "absent"), (5, "unmarked")]
        for (day, status) in statuses {
            let record = CDAttendanceRecord(context: ctx)
            record.id = UUID()
            record.studentID = studentID
            record.date = date(2026, 9, day)
            record.statusRaw = status
        }
        #expect(CoreDataTestHelpers.save(ctx))

        let context = makeBuilder(ctx).buildContext(for: student, month: month, includeStudentReflection: false)
        let attendance = try #require(context.attendance)
        #expect(attendance.daysPresent == 3) // present, present, tardy
        #expect(attendance.daysAbsent == 1)
        #expect(attendance.tardies == 1)
        #expect(attendance.markedDays == 4)
    }
}
