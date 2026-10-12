//
//  MarkLessonPresentedIntent.swift
//  Cosmic Daybook
//
//  Records that a lesson was presented to a student — by voice or from
//  Shortcuts, without opening the app. Reuses an existing draft/scheduled
//  presentation for that lesson+student when one exists — splitting the
//  student out via PresentationSplitService when the assignment covers a
//  group, so classmates aren't marked presented too. Otherwise creates a
//  new one. Marking uses CDLessonAssignment.markPresented (the canonical path).
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

        // Reuse an existing not-yet-presented assignment for this lesson + student.
        let existing = cdLesson.lessonAssignments.first {
            !$0.isPresented && $0.studentIDs.contains(studentID.uuidString)
        }

        let assignment: CDLessonAssignment
        if let existing {
            // A group assignment must be split first (same path as the UI) so
            // only this student is recorded as presented; the classmates keep
            // their original, unpresented assignment.
            if existing.studentIDs.count > 1,
               let split = PresentationSplitService.splitReadyStudents(
                   from: existing,
                   readyStudentIDs: [studentID],
                   asDraft: true,
                   context: context
               ) {
                assignment = split
            } else {
                assignment = existing
            }
        } else {
            assignment = PresentationFactory.makeDraft(
                lesson: cdLesson,
                students: [cdStudent],
                context: context
            )
        }
        do {
            _ = try LifecycleService.recordPresentation(
                from: assignment,
                presentedAt: Date(),
                modelContext: context
            )
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
        return .result(dialog: "Marked \(cdLesson.name) as presented to \(cdStudent.shortName).")
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
