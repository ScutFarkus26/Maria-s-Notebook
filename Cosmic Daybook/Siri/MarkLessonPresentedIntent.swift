//
//  MarkLessonPresentedIntent.swift
//  Cosmic Daybook
//
//  Records that a lesson was presented to a student — by voice or from
//  Shortcuts, without opening the app. The presentation is the one
//  `PresentationRecorder.resolvePlan` picks: one already given to her that
//  day (nothing more is recorded), a waiting plan (split when it covers a
//  group, so classmates aren't marked presented too), or a new one.
//

import AppIntents
import CoreData
import OSLog

struct MarkLessonPresentedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Lesson Presented"
    static let description = IntentDescription(
        "Record that a lesson was presented to a student.",
        categoryName: "Lessons"
    )
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Lesson")
    var lesson: LessonEntity

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$lesson) as presented to \(\.$student)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try await AppBootstrapping.sharedCoreDataStackForIntent().viewContext

        guard let cdLesson = context.object(CDLesson.self, id: lesson.id), cdLesson.id != nil else {
            throw MarkLessonPresentedError.lessonNotFound(lesson.name)
        }

        let (cdStudent, studentID) = try classStudent(in: context)

        // Marking a presentation changes curriculum history. Confirm after
        // resolving the exact lesson and child, before splitting or creating data.
        try await requestConfirmation()

        let origin: PresentationRecorder.PlanOrigin
        do {
            origin = try Self.record(cdLesson, for: cdStudent, on: Date(), in: context)
        } catch {
            // The raw error would reach Siri as system text; it goes to the log instead.
            let ns = error as NSError
            Logger.database.error("""
                Siri couldn't record a presentation: \(ns.domain, privacy: .public) \
                \(ns.code, privacy: .public) \(ns.localizedDescription, privacy: .public)
                """)
            throw MarkLessonPresentedError.saveFailed
        }

        guard context.safeSave() else { throw MarkLessonPresentedError.saveFailed }

        Logger.database.info("Marked lesson presented via Siri for student \(studentID.uuidString, privacy: .public)")
        // The short name, so the two Ettys are told apart ("Etty D").
        if origin == .alreadyRecorded {
            return .result(dialog: "\(cdLesson.name) was already marked as presented to \(cdStudent.shortName) today.")
        }
        return .result(dialog: "Marked \(cdLesson.name) as presented to \(cdStudent.shortName).")
    }

    /// Records the lesson as given to her on `day`, on the presentation the app's
    /// one rule picks (`PresentationRecorder.resolvePlan`, domain logic review
    /// 2026-11-20, R12): one already given to her that day is left as it is, so a
    /// second "presented" makes no second record; a plan waiting for her (split
    /// off a group plan, so classmates keep theirs) comes next; then a new one.
    @MainActor
    @discardableResult
    static func record(
        _ lesson: CDLesson, for student: CDStudent, on day: Date, in context: NSManagedObjectContext
    ) throws -> PresentationRecorder.PlanOrigin {
        let resolved = PresentationRecorder.resolvePlan(lesson: lesson, present: [student], on: day, context: context)
        try PresentationRecorder.recordResolved(resolved, on: day, context: context)
        return resolved.origin
    }

    /// The chosen child, if she is still in the class. The name query falls
    /// back to children who have left, so "Open Leah" still finds her; a
    /// lesson is recorded only for a child on the roll (2026-10-11 hunt, #37).
    @MainActor
    private func classStudent(in context: NSManagedObjectContext) throws -> (CDStudent, UUID) {
        guard let cdStudent = context.object(CDStudent.self, id: student.id), let studentID = cdStudent.id else {
            throw MarkLessonPresentedError.studentNotFound(student.fullName)
        }
        guard SiriHost.roster(in: context).contains(cdStudent) else {
            throw MarkLessonPresentedError.notInClass(cdStudent.shortName)
        }
        return (cdStudent, studentID)
    }
}

// MARK: - Errors

enum MarkLessonPresentedError: Error, CustomLocalizedStringResourceConvertible {
    case lessonNotFound(String)
    case studentNotFound(String)
    case notInClass(String)
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .lessonNotFound(let name):
            return "I couldn't find the lesson \(name)."
        case .studentNotFound(let name):
            return "I couldn't find \(name) in your students."
        case .notInClass(let name):
            return "\(name) isn't in your class anymore, so nothing was marked."
        case .saveFailed:
            return "Something went wrong saving the presentation. Try again."
        }
    }
}
