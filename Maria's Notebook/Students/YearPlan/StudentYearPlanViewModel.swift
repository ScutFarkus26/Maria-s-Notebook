import Foundation
import CoreData

@Observable
final class StudentYearPlanViewModel {

    private(set) var entries: [CDYearPlanEntry] = []
    private(set) var lessonsByID: [String: CDLesson] = [:]

    /// Which of this child's intentions the presentation record already
    /// answers. Read once per `load` — see `YearPlanSatisfaction`.
    private(set) var satisfaction: YearPlanSatisfaction = .none

    /// Targets still ahead that sit on days the school is closed. The guide has
    /// nothing to do about these by hand — the calendar moved under the plan —
    /// so they are the second reason to offer Readjust. Counted at load, not in
    /// `body`.
    private(set) var closedDayCount: Int = 0

    /// The first day of the school year containing today. Read once per `load`
    /// and handed to every pace question below: `isBehindPace` is evaluated per
    /// calendar cell per render, and the boundary cannot change mid-pass.
    private(set) var yearStart: Date = YearPlanStaleness.currentYearStart()

    private var itemsByCell: [CellID: [YearPlanCalendarItem]] = [:]

    func items(for cellID: CellID) -> [YearPlanCalendarItem] {
        itemsByCell[cellID] ?? []
    }

    func load(studentID: UUID?, context: NSManagedObjectContext) {
        guard let studentID else { return }
        let studentIDString = studentID.uuidString
        yearStart = YearPlanStaleness.currentYearStart()

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
        closedDayCount = entriesStillAhead
            .filter { YearPlanPacing.fallsOnClosedDay($0, in: context) }
            .count
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
                    satisfaction: satisfaction,
                    yearStart: yearStart
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
                    kind: .assignment(assignment),
                    yearStart: yearStart
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
    ///
    /// A drop onto a day the school is closed lands on the next open day — the
    /// guide is asking for "about here", and no lesson is given on Rosh Hashana.
    func rescheduleWithCascade(
        _ entry: CDYearPlanEntry,
        to newDate: Date,
        studentID: UUID,
        context: NSManagedObjectContext
    ) async {
        let landing = YearPlanPacing.schoolDay(onOrAfter: newDate, in: context)
        entry.plannedDate = landing
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

        var currentDate = landing
        for next in subsequent {
            currentDate = YearPlanPacing.advance(
                from: currentDate, bySchoolDays: next.spacingSchoolDays, in: context
            )
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

    /// Readjust the entries still ahead of this child, sequence by sequence.
    ///
    /// Two things send a sequence back to the drawing board, and they are
    /// handled differently. A sequence whose first entry has fallen behind pace
    /// is re-laid from the next school day — it has slipped as a whole. A
    /// sequence that is on time but has targets sitting on days the school is
    /// closed is only nudged: those entries move to the open days around them
    /// (`YearPlanPacing.resettle`) and the ones already on good days keep the
    /// dates the guide chose.
    func readjust(studentID: UUID, context: NSManagedObjectContext) async {
        let today = AppCalendar.startOfDay(Date())
        let stillAhead = entries.filter { $0.isPlanned && !$0.isSatisfied(by: satisfaction) }
        let grouped = Dictionary(grouping: stillAhead) { $0.sequenceGroupKey }

        for (_, sequenceEntries) in grouped {
            let sorted = YearPlanPacing.inSequenceOrder(sequenceEntries)
            guard let first = sorted.first, let firstDate = first.plannedDate else { continue }

            if firstDate < today {
                var currentDate = YearPlanPacing.schoolDay(
                    onOrAfter: AppCalendar.addingDays(1, to: today), in: context
                )
                first.plannedDate = currentDate
                first.modifiedAt = Date()

                for entry in sorted.dropFirst() {
                    currentDate = YearPlanPacing.advance(
                        from: currentDate, bySchoolDays: entry.spacingSchoolDays, in: context
                    )
                    entry.plannedDate = currentDate
                    entry.modifiedAt = Date()
                }
            } else {
                YearPlanPacing.resettle(sorted, in: context)
            }
        }

        context.safeSave()
        load(studentID: studentID, context: context)
    }

    var behindPaceCount: Int {
        entries.filter { $0.isBehindPace(satisfiedBy: satisfaction, schoolYearStart: yearStart) }.count
    }

    /// Entries whose target fell in a school year that has ended. Not debt —
    /// the header says so in its own words, and Readjust re-lays them.
    var carriedOverCount: Int {
        let start = yearStart
        return entries.filter { entry in
            entry.isCarriedOver(yearStart: start) && !entry.isSatisfied(by: satisfaction)
        }.count
    }

    /// The label a carried-over chip names, e.g. "2025–2026".
    var previousYearLabel: String {
        YearPlanStaleness.previousSchoolYear().label
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
