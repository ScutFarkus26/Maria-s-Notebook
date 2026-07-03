//
//  MarkLessonPresentedIntent.swift
//  Maria's Notebook
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

    @Parameter(title: "Lesson")
    var lesson: LessonEntity

    @Parameter(title: "Student")
    var student: StudentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$lesson) as presented to \(\.$student)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppBootstrapping.getSharedCoreDataStack().viewContext

        let lessonRequest = CDFetchRequest(CDLesson.self)
        lessonRequest.predicate = NSPredicate(format: "id == %@", lesson.id as CVarArg)
        lessonRequest.fetchLimit = 1
        guard let cdLesson = context.safeFetchFirst(lessonRequest), cdLesson.id != nil else {
            throw MarkLessonPresentedError.lessonNotFound(lesson.name)
        }

        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(format: "id == %@", student.id as CVarArg)
        studentRequest.fetchLimit = 1
        guard let cdStudent = context.safeFetchFirst(studentRequest), let studentID = cdStudent.id else {
            throw MarkLessonPresentedError.studentNotFound(student.fullName)
        }

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
        assignment.markPresented()

        guard context.safeSave() else { throw MarkLessonPresentedError.saveFailed }

        Logger.database.info("Marked lesson presented via Siri for student \(studentID.uuidString, privacy: .public)")
        return .result(dialog: "Marked \(cdLesson.name) as presented to \(cdStudent.firstName).")
    }
}

// MARK: - Errors

enum MarkLessonPresentedError: Error, CustomLocalizedStringResourceConvertible {
    case lessonNotFound(String)
    case studentNotFound(String)
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .lessonNotFound(let name):
            return "I couldn't find the lesson \(name)."
        case .studentNotFound(let name):
            return "I couldn't find \(name) in your students."
        case .saveFailed:
            return "Something went wrong saving the presentation. Please try again."
        }
    }
}
