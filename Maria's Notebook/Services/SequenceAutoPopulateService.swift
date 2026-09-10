import Foundation
import CoreData
import OSLog

/// Auto-populates CDYearPlanEntry records for an entire lesson sequence
/// when a presentation is scheduled (moved from inbox to the calendar).
/// Only creates entries that don't already exist — respects manually created sequences.
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

        let area = lesson.area.trimmed()
        let sequence = lesson.sequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty else { return }

        // Fetch all lessons in same area + sequence, sorted by orderInSequence
        let lessonReq = CDFetchRequest(CDLesson.self)
        lessonReq.predicate = NSPredicate(
            format: "area ==[c] %@ AND sequence ==[c] %@",
            area, sequence
        )
        lessonReq.sortDescriptors = [NSSortDescriptor(key: "orderInSequence", ascending: true)]
        let allInSequence = context.safeFetch(lessonReq)

        // Filter to lessons at or after the current lesson's position
        let lessonsAhead = allInSequence.filter { $0.orderInSequence >= lesson.orderInSequence }
        guard !lessonsAhead.isEmpty else { return }

        let sequenceKey = "\(area)::\(sequence)"
        // A child who has withdrawn or transferred gets no new intentions. The
        // departure cascade skips the entries she already had (see
        // StudentDeparturePlans); minting more here would put them straight
        // back, dated into a year she will not be here for. A student record
        // that cannot be found is left alone rather than silently dropped.
        let studentIDs: [UUID] = assignment.studentUUIDs.filter { studentID in
            let student: CDStudent? = context.object(CDStudent.self, id: studentID)
            return student?.isEnrolled ?? true
        }
        guard !studentIDs.isEmpty else { return }

        let defaultSpacing: Int64 = 3
        // The lessons after the first were always spaced in *school* days; the
        // first one used to take the scheduled date as given, which is how a
        // sequence started on a day the school is closed. One rule for both now.
        let scheduledDateNormalized: Date = YearPlanPacing.schoolDay(
            onOrAfter: scheduledDate, in: context
        )

        for studentID in studentIDs {
            let studentIDStr = studentID.uuidString
            var currentDate: Date = scheduledDateNormalized

            for (index, lessonInSequence) in lessonsAhead.enumerated() {
                let lessonIDStr = lessonInSequence.id?.uuidString ?? ""
                guard !lessonIDStr.isEmpty else { continue }

                // Compute date: first entry uses scheduledDate, rest are spaced
                if index > 0 {
                    let next: Date = YearPlanPacing.advance(
                        from: currentDate, bySchoolDays: defaultSpacing, in: context
                    )
                    currentDate = next
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
                entry.sequenceGroupKey = sequenceKey
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
        logger.info("Auto-populated \(sequence.count) entries for \(studentIDs.count) student(s) in \(sequenceKey)")
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
