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

        // 2. Her scheduled or presented assignments
        let studentAssignments = Self.assignments(for: studentIDString, in: context)

        // 3. Put the entries right against them and their lessons before
        // drawing (`YearPlanEntryRepair`), then re-read them in date order.
        lessonsByID = Self.lessons(withIDs: Set(entries.map(\.lessonID)), in: context)
        if repairEntries(against: studentAssignments, in: context) {
            entries = context.safeFetch(entryReq)
        }

        // Exclude assignments already represented by a promoted Year Plan entry
        let promotedIDs = Set(entries.compactMap(\.promotedAssignmentID))
        let unlinkedAssignments = studentAssignments.filter { assignment in
            guard let assignmentID = assignment.id?.uuidString else { return false }
            return !promotedIDs.contains(assignmentID)
        }
        let assignmentLessonIDs = Set(unlinkedAssignments.map(\.lessonID)).subtracting(lessonsByID.keys)
        lessonsByID.merge(Self.lessons(withIDs: assignmentLessonIDs, in: context)) { first, _ in first }

        // 4. Build unified cell lookup
        itemsByCell = buildCells(
            assignments: unlinkedAssignments,
            linkedDates: Self.presentationDays(of: studentAssignments, promotedIDs: promotedIDs)
        )
        closedDayCount = closedDayEntries(in: context).count
    }

    /// Her assignments that are on the calendar or given.
    private static func assignments(
        for studentID: String, in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let assignmentReq = CDFetchRequest(CDLessonAssignment.self)
        assignmentReq.predicate = NSPredicate(
            format: "scheduledFor != nil OR presentedAt != nil"
        )
        return context.safeFetch(assignmentReq).filter {
            $0.studentIDs.contains(studentID)
        }
    }

    private static func lessons(
        withIDs ids: Set<String>, in context: NSManagedObjectContext
    ) -> [String: CDLesson] {
        var lookup: [String: CDLesson] = [:]
        for idStr in ids where !idStr.isEmpty {
            if let uuid = UUID(uuidString: idStr),
               let lesson = context.object(CDLesson.self, id: uuid) {
                lookup[idStr] = lesson
            }
        }
        return lookup
    }

    /// The day each linked presentation is on or was given, by its id: a
    /// promoted entry is drawn there, where the calendar shows it, rather
    /// than on the day it was first promoted for (bug hunt 2026-11-03 #20).
    private static func presentationDays(
        of assignments: [CDLessonAssignment], promotedIDs: Set<String>
    ) -> [String: Date] {
        var days: [String: Date] = [:]
        for assignment in assignments {
            guard let id = assignment.id?.uuidString, promotedIDs.contains(id),
                  let date = assignment.scheduledFor ?? assignment.presentedAt else { continue }
            days[id] = date
        }
        return days
    }

    /// The load's repair, saved when it changed anything. When the context
    /// already holds someone else's unsaved change, the repaired values wait
    /// for that save rather than a load saving it for them. Returns whether
    /// any entry changed.
    private func repairEntries(
        against assignments: [CDLessonAssignment], in context: NSManagedObjectContext
    ) -> Bool {
        let wasClean = !context.hasChanges
        let repaired = YearPlanEntryRepair.repair(
            entries, lessonsByID: lessonsByID, assignments: assignments
        )
        guard repaired > 0 else { return false }
        if wasClean { context.safeSave() }
        return true
    }

    /// Planned targets from today on that sit on days the school is closed:
    /// the ones Readjust moves. Promoted entries are real assignments it
    /// leaves alone, and a target already past isn't one still ahead, so
    /// counting either kept the warning up after Readjust (bug hunt
    /// 2026-10-12 #53).
    private func closedDayEntries(in context: NSManagedObjectContext) -> [CDYearPlanEntry] {
        let today = AppCalendar.startOfDay(Date())
        return entries.filter { entry in
            guard entry.isPlanned, !entry.isSatisfied(by: satisfaction),
                  let date = entry.plannedDate, AppCalendar.startOfDay(date) >= today
            else { return false }
            return YearPlanPacing.fallsOnClosedDay(entry, in: context)
        }
    }

    /// Lays the entries and the assignments nothing links to onto calendar
    /// days, a promoted entry on its presentation's day (`linkedDates`). Each
    /// item's display status is resolved here, once, because
    /// `YearPlanSatisfaction` reads the store and the calendar asks for it per
    /// cell per render.
    private func buildCells(
        assignments: [CDLessonAssignment], linkedDates: [String: Date]
    ) -> [CellID: [YearPlanCalendarItem]] {
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
            let linked = entry.isPromoted ? entry.promotedAssignmentID.flatMap { linkedDates[$0] } : nil
            guard let date = linked ?? entry.plannedDate, let entryID = entry.id else { continue }
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
        // The planned entries after this one in its sequence, in the order it
        // is given: the lessons' own order (the load renumbers entries from
        // their lessons, bug hunt 2026-11-03 #24), the target date for a tie.
        // Read before the move, so its new date doesn't change its place.
        let sequence = YearPlanPacing.inSequenceOrder(entries.filter {
            $0 === entry || (
                $0.sequenceGroupKey == entry.sequenceGroupKey &&
                $0.studentID == entry.studentID &&
                $0.isPlanned && !$0.isSatisfied(by: satisfaction)
            )
        })
        let position = sequence.firstIndex(where: { $0 === entry }) ?? sequence.endIndex
        let subsequent = sequence.suffix(from: min(position + 1, sequence.endIndex))

        let landing = YearPlanPacing.schoolDay(onOrAfter: newDate, in: context)
        entry.plannedDate = landing
        entry.modifiedAt = Date()

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
