import Foundation
import CoreData

@Observable
@MainActor
final class StudentYearPlanViewModel {

    private(set) var entries: [CDYearPlanEntry] = []
    private(set) var lessonsByID: [String: CDLesson] = [:]

    private var itemsByCell: [CellID: [YearPlanCalendarItem]] = [:]

    func items(for cellID: CellID) -> [YearPlanCalendarItem] {
        itemsByCell[cellID] ?? []
    }

    func load(studentID: UUID?, context: NSManagedObjectContext) {
        guard let studentID else { return }
        let studentIDString = studentID.uuidString

        // 1. Fetch Year Plan entries for this student
        let entryReq = CDFetchRequest(CDYearPlanEntry.self)
        entryReq.predicate = NSPredicate(format: "studentID == %@", studentIDString)
        entryReq.sortDescriptors = [NSSortDescriptor(key: "plannedDate", ascending: true)]
        entries = context.safeFetch(entryReq)

        // 2. Fetch scheduled or presented assignments
        let assignmentReq = CDFetchRequest(CDLessonAssignment.self)
        assignmentReq.predicate = NSPredicate(
            format: "scheduledFor != nil OR presentedAt != nil"
        )
        let allAssignments = context.safeFetch(assignmentReq)

        // Filter to this student's assignments
        let studentAssignments = allAssignments.filter {
            $0.studentIDs.contains(studentIDString)
        }

        // Exclude assignments already represented by a promoted Year Plan entry
        let promotedIDs = Set(entries.compactMap(\.promotedAssignmentID))
        let unlinkedAssignments = studentAssignments.filter { assignment in
            guard let assignmentID = assignment.id?.uuidString else { return false }
            return !promotedIDs.contains(assignmentID)
        }

        // 3. Build lessons lookup from both sources
        let entryLessonIDs = Set(entries.map(\.lessonID))
        let assignmentLessonIDs = Set(unlinkedAssignments.map(\.lessonID))
        let allLessonIDs = entryLessonIDs.union(assignmentLessonIDs)

        var lookup: [String: CDLesson] = [:]
        for idStr in allLessonIDs where !idStr.isEmpty {
            let lessonReq = CDFetchRequest(CDLesson.self)
            lessonReq.predicate = NSPredicate(format: "id == %@", idStr)
            lessonReq.fetchLimit = 1
            if let lesson = context.safeFetchFirst(lessonReq) {
                lookup[idStr] = lesson
            }
        }
        lessonsByID = lookup

        // 4. Build unified cell lookup
        let cal = AppCalendar.shared
        var cellLookup: [CellID: [YearPlanCalendarItem]] = [:]

        for entry in entries {
            guard let date = entry.plannedDate, let entryID = entry.id else { continue }
            let cellID = CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            )
            cellLookup[cellID, default: []].append(
                YearPlanCalendarItem(id: entryID, lessonID: entry.lessonID, date: date, kind: .planEntry(entry))
            )
        }

        for assignment in unlinkedAssignments {
            let date = assignment.scheduledFor ?? assignment.presentedAt
            guard let date, let assignmentID = assignment.id else { continue }
            let cellID = CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            )
            cellLookup[cellID, default: []].append(
                YearPlanCalendarItem(id: assignmentID, lessonID: assignment.lessonID, date: date, kind: .assignment(assignment))
            )
        }

        itemsByCell = cellLookup
    }

    func lessonFor(_ entry: CDYearPlanEntry) -> CDLesson? {
        lessonsByID[entry.lessonID]
    }

    func removeEntry(_ entry: CDYearPlanEntry, context: NSManagedObjectContext) {
        context.delete(entry)
        context.safeSave()
    }

    func rescheduleEntry(_ entry: CDYearPlanEntry, to newDate: Date, context: NSManagedObjectContext) {
        entry.plannedDate = AppCalendar.startOfDay(newDate)
        entry.modifiedAt = Date()
        context.safeSave()
    }

    /// Readjust all future planned entries in all sequences for this student.
    func readjust(studentID: UUID, context: NSManagedObjectContext) async {
        let today = AppCalendar.startOfDay(Date())

        let grouped = Dictionary(grouping: entries.filter { $0.isPlanned }) { $0.sequenceGroupKey }

        for (_, sequenceEntries) in grouped {
            let sorted = sequenceEntries.sorted { $0.orderInSequence < $1.orderInSequence }
            guard let first = sorted.first else { continue }

            guard let firstDate = first.plannedDate, firstDate < today else { continue }

            var currentDate = await SchoolCalendar.nextSchoolDay(after: today, using: context)
            first.plannedDate = currentDate
            first.modifiedAt = Date()

            for entry in sorted.dropFirst() {
                for _ in 0..<max(1, entry.spacingSchoolDays) {
                    currentDate = await SchoolCalendar.nextSchoolDay(after: currentDate, using: context)
                }
                entry.plannedDate = currentDate
                entry.modifiedAt = Date()
            }
        }

        context.safeSave()
        load(studentID: studentID, context: context)
    }

    var behindPaceCount: Int {
        entries.filter(\.isBehindPace).count
    }
}
