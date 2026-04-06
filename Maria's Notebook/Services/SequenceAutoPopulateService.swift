import Foundation
import CoreData
import OSLog

/// Auto-populates CDYearPlanEntry records for an entire lesson sequence
/// when a presentation is scheduled (moved from inbox to the calendar).
/// Only creates entries that don't already exist — respects manually created sequences.
@MainActor
enum SequenceAutoPopulateService {
    private static let logger = Logger.app(category: "SequenceAutoPopulate")

    /// Creates CDYearPlanEntry records for all remaining lessons in the sequence
    /// when a presentation is scheduled.
    static func autoPopulateSequence(
        for assignment: CDLessonAssignment,
        scheduledDate: Date,
        context: NSManagedObjectContext
    ) async {
        guard let lesson = assignment.lesson else {
            logger.warning("No lesson found for assignment \(assignment.lessonID)")
            return
        }

        let subject = lesson.subject.trimmed()
        let group = lesson.group.trimmed()
        guard !subject.isEmpty, !group.isEmpty else { return }

        // Fetch all lessons in same subject + group, sorted by orderInGroup
        let lessonReq = CDFetchRequest(CDLesson.self)
        lessonReq.predicate = NSPredicate(
            format: "subject ==[c] %@ AND group ==[c] %@",
            subject, group
        )
        lessonReq.sortDescriptors = [NSSortDescriptor(key: "orderInGroup", ascending: true)]
        let allInGroup = context.safeFetch(lessonReq)

        // Filter to lessons at or after the current lesson's position
        let sequence = allInGroup.filter { $0.orderInGroup >= lesson.orderInGroup }
        guard !sequence.isEmpty else { return }

        let sequenceGroupKey = "\(subject)::\(group)"
        let studentIDs = assignment.studentUUIDs
        guard !studentIDs.isEmpty else { return }

        let defaultSpacing: Int64 = 3
        let scheduledDateNormalized = AppCalendar.startOfDay(scheduledDate)

        for studentID in studentIDs {
            let studentIDStr = studentID.uuidString
            var currentDate = scheduledDateNormalized

            for (index, lessonInSequence) in sequence.enumerated() {
                let lessonIDStr = lessonInSequence.id?.uuidString ?? ""
                guard !lessonIDStr.isEmpty else { continue }

                // Compute date: first entry uses scheduledDate, rest are spaced
                if index > 0 {
                    for _ in 0..<defaultSpacing {
                        currentDate = await SchoolCalendar.nextSchoolDay(
                            after: currentDate, using: context
                        )
                    }
                }

                let isFirstEntry = (index == 0)

                // Check for existing entry
                if let existing = existingEntry(
                    lessonID: lessonIDStr, studentID: studentIDStr, context: context
                ) {
                    // If this is the lesson being scheduled, promote the existing entry
                    if isFirstEntry, existing.isPlanned {
                        existing.status = .promoted
                        existing.promotedAssignmentID = assignment.id?.uuidString
                        existing.plannedDate = currentDate
                        existing.modifiedAt = Date()
                    }
                    // Otherwise skip — entry already exists
                    continue
                }

                // Create new entry
                let entry = CDYearPlanEntry(context: context)
                entry.studentID = studentIDStr
                entry.lessonID = lessonIDStr
                entry.plannedDate = currentDate
                entry.spacingSchoolDays = defaultSpacing
                entry.sequenceGroupKey = sequenceGroupKey
                entry.orderInSequence = Int64(index)

                if isFirstEntry {
                    entry.status = .promoted
                    entry.promotedAssignmentID = assignment.id?.uuidString
                } else {
                    entry.status = .planned
                }
            }
        }

        context.safeSave()
        logger.info("Auto-populated \(sequence.count) entries for \(studentIDs.count) student(s) in \(sequenceGroupKey)")
    }

    // MARK: - Helpers

    private static func existingEntry(
        lessonID: String,
        studentID: String,
        context: NSManagedObjectContext
    ) -> CDYearPlanEntry? {
        let req = CDFetchRequest(CDYearPlanEntry.self)
        req.predicate = NSPredicate(
            format: "lessonID == %@ AND studentID == %@",
            lessonID, studentID
        )
        req.fetchLimit = 1
        return context.safeFetchFirst(req)
    }
}
