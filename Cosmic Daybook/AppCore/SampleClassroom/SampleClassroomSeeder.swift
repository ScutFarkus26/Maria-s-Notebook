import CoreData
import Foundation

/// Builds and maintains the isolated Sample Class data set.
///
/// The lesson catalog is mirrored by value, with the same stable lesson IDs,
/// into the sample store. Student records and all activity records are created
/// only in that sample store. No managed object is ever shared between the two
/// contexts.
enum SampleClassroomSeeder {
    struct AttachmentSnapshot {
        let id: UUID
        let fileName: String
        let fileBookmark: Data?
        let fileRelativePath: String
        let attachedAt: Date?
        let fileType: String
        let fileSizeBytes: Int64
        let scopeRaw: String
        let notes: String
        let thumbnailData: Data?
    }

    struct SampleWorkStepSnapshot {
        let id: UUID
        let title: String
        let orderIndex: Int64
        let instructions: String
        let createdAt: Date?
    }

    struct SampleWorkSnapshot {
        let id: UUID
        let title: String
        let workKindRaw: String
        let orderIndex: Int64
        let notes: String
        let createdAt: Date?
        let steps: [SampleWorkStepSnapshot]
    }

    struct LessonSnapshot {
        let id: UUID
        let name: String
        let area: String
        let sequence: String
        let orderInSequence: Int64
        let sortIndex: Int64
        let section: String
        let writeUp: String
        let suggestedFollowUpWork: String
        let materials: String
        let purpose: String
        let ageRange: String
        let teacherNotes: String
        let prerequisiteLessonIDs: String
        let relatedLessonIDs: String
        let greatLessonRaw: String?
        let sourceRaw: String
        let personalKindRaw: String?
        let lessonFormatRaw: String
        let parentStoryID: String?
        let defaultWorkKindRaw: String?
        let pagesFileBookmark: Data?
        let pagesFileRelativePath: String?
        let primaryAttachmentID: String?
        let requiresPracticeOverride: String
        let requiresConfirmationOverride: String
        let parshaKey: String?
        let derivedFromLessonID: String?
        let attachments: [AttachmentSnapshot]
        let sampleWorks: [SampleWorkSnapshot]
    }

    static func prepare(
        lessonsFrom sourceContext: NSManagedObjectContext,
        sampleContext: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) throws {
        let lessons = try lessonSnapshots(from: sourceContext)

        do {
            try mirror(lessons: lessons, into: sampleContext)
            try seedStudentsIfNeeded(in: sampleContext, now: now, calendar: calendar)
            try seedAttendanceIfNeeded(in: sampleContext, now: now, calendar: calendar)
            try seedLessonActivityIfNeeded(
                lessons: lessons,
                in: sampleContext,
                now: now,
                calendar: calendar
            )
            try seedNotesIfNeeded(in: sampleContext, now: now, calendar: calendar)

            if sampleContext.hasChanges {
                try sampleContext.save()
            }
        } catch {
            sampleContext.rollback()
            throw error
        }
    }
}
