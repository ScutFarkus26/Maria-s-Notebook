import Foundation
import CoreData

@Observable
final class StudentYearPlanViewModel {

    private(set) var entries: [CDYearPlanEntry] = []
    private(set) var lessonsByID: [String: CDLesson] = [:]

    /// Which of this child's intentions the presentation record already
    /// answers. Read once per `load` — see `YearPlanSatisfaction`.
    private(set) var satisfaction: YearPlanSatisfaction = .none

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
        satisfaction = YearPlanSatisfaction.index(forStudents: [studentIDString], in: context)

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
            if let uuid = UUID(uuidString: idStr),
               let lesson = context.object(CDLesson.self, id: uuid) {
                lookup[idStr] = lesson
            }
        }
        lessonsByID = lookup

        // 4. Build unified cell lookup
        itemsByCell = buildCells(assignments: unlinkedAssignments)
    }

    /// Lays the entries and the assignments nothing links to onto calendar
    /// days. Each item's display status is resolved here, once, because
    /// `YearPlanSatisfaction` reads the store and the calendar asks for it per
    /// cell per render.
    private func buildCells(assignments: [CDLessonAssignment]) -> [CellID: [YearPlanCalendarItem]] {
        let cal = AppCalendar.shared
        var cellLookup: [CellID: [YearPlanCalendarItem]] = [:]

        func cellID(for date: Date) -> CellID {
            CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            )
        }

        for entry in entries {
            guard let date = entry.plannedDate, let entryID = entry.id else { continue }
            cellLookup[cellID(for: date), default: []].append(
                YearPlanCalendarItem(
                    id: entryID,
                    lessonID: entry.lessonID,
                    date: date,
                    kind: .planEntry(entry),
                    satisfaction: satisfaction
                )
            )
        }

        for assignment in assignments {
            let date = assignment.scheduledFor ?? assignment.presentedAt
            guard let date, let assignmentID = assignment.id else { continue }
            cellLookup[cellID(for: date), default: []].append(
                YearPlanCalendarItem(
                    id: assignmentID,
                    lessonID: assignment.lessonID,
                    date: date,
                    kind: .assignment(assignment)
                )
            )
        }

        return cellLookup
    }

    func removeEntry(_ entry: CDYearPlanEntry, context: NSManagedObjectContext) {
        context.delete(entry)
        context.safeSave()
    }

    /// Reschedules an entry and cascades the shift to all subsequent planned entries
    /// in the same sequence, maintaining spacing.
    func rescheduleWithCascade(
        _ entry: CDYearPlanEntry,
        to newDate: Date,
        studentID: UUID,
        context: NSManagedObjectContext
    ) async {
        let newDateNormalized = AppCalendar.startOfDay(newDate)
        entry.plannedDate = newDateNormalized
        entry.modifiedAt = Date()

        // Find all planned entries in the same sequence after this one
        let subsequent = entries
            .filter {
                $0.sequenceGroupKey == entry.sequenceGroupKey &&
                $0.studentID == entry.studentID &&
                $0.orderInSequence > entry.orderInSequence &&
                $0.isPlanned && !$0.isSatisfied(by: satisfaction)
            }
            .sorted { $0.orderInSequence < $1.orderInSequence }

        var currentDate = newDateNormalized
        for next in subsequent {
            for _ in 0..<max(1, next.spacingSchoolDays) {
                currentDate = await SchoolCalendarService.shared.nextSchoolDay(after: currentDate, using: context)
            }
            next.plannedDate = currentDate
            next.modifiedAt = Date()
        }

        context.safeSave()
        load(studentID: studentID, context: context)
    }

    /// Finds a CDYearPlanEntry by ID from the loaded entries.
    func entry(byID id: UUID) -> CDYearPlanEntry? {
        entries.first { $0.id == id }
    }

    /// Readjust all future planned entries in all sequences for this student.
    func readjust(studentID: UUID, context: NSManagedObjectContext) async {
        let today = AppCalendar.startOfDay(Date())

        let stillAhead = entries.filter { $0.isPlanned && !$0.isSatisfied(by: satisfaction) }
        let grouped = Dictionary(grouping: stillAhead) { $0.sequenceGroupKey }

        for (_, sequenceEntries) in grouped {
            let sorted = sequenceEntries.sorted { $0.orderInSequence < $1.orderInSequence }
            guard let first = sorted.first else { continue }

            guard let firstDate = first.plannedDate, firstDate < today else { continue }

            var currentDate = await SchoolCalendarService.shared.nextSchoolDay(after: today, using: context)
            first.plannedDate = currentDate
            first.modifiedAt = Date()

            for entry in sorted.dropFirst() {
                for _ in 0..<max(1, entry.spacingSchoolDays) {
                    currentDate = await SchoolCalendarService.shared.nextSchoolDay(after: currentDate, using: context)
                }
                entry.plannedDate = currentDate
                entry.modifiedAt = Date()
            }
        }

        context.safeSave()
        load(studentID: studentID, context: context)
    }

    var behindPaceCount: Int {
        entries.filter { $0.isBehindPace(satisfiedBy: satisfaction) }.count
    }

    /// Entries still ahead of this child: pencilled in or on the calendar, and
    /// not answered by a lesson already given. The number the pace summary
    /// counts, and the gate on showing it at all.
    var openEntryCount: Int {
        entriesStillAhead.count
    }

    /// The entries every pace measurement is taken over.
    private var entriesStillAhead: [CDYearPlanEntry] {
        entries.filter {
            ($0.isPlanned || $0.isPromoted) && !$0.isSatisfied(by: satisfaction)
        }
    }

    /// Average spacing in days between consecutive planned entries.
    var averageSpacingDays: Double? {
        let planned = entriesStillAhead
            .compactMap(\.plannedDate)
            .sorted()
        guard planned.count >= 2 else { return nil }

        let cal = AppCalendar.shared
        var totalDays = 0
        for idx in 1..<planned.count {
            totalDays += cal.dateComponents([.day], from: planned[idx - 1], to: planned[idx]).day ?? 0
        }
        return Double(totalDays) / Double(planned.count - 1)
    }

    /// Number of consecutive entries that are compressed (spacing < 2 days).
    var compressedCount: Int {
        let planned = entriesStillAhead
            .compactMap(\.plannedDate)
            .sorted()
        guard planned.count >= 2 else { return 0 }

        let cal = AppCalendar.shared
        var count = 0
        for idx in 1..<planned.count {
            let days = cal.dateComponents([.day], from: planned[idx - 1], to: planned[idx]).day ?? 0
            if days < 2 { count += 1 }
        }
        return count
    }
}
