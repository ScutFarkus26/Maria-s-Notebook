// WorksAgendaView+DataHelpers.swift
// Cache loading, filtering, and display helpers for WorksAgendaView.

import SwiftUI
import CoreData
import OSLog

extension WorksAgendaView {

    // MARK: - Change Detection

    /// PERF: Lightweight change detection using fetchCount() instead of loading full tables.
    ///
    /// Returns true when a token moved, which changes `dataReloadTrigger` and
    /// so schedules `loadLessonsAndStudentsIfNeeded` (and the partition
    /// rebuild it ends with) on its own.
    @discardableResult
    func refreshChangeTokens() -> Bool {
        var changed = false
        do {
            let lRequest = CDFetchRequest(CDLesson.self)
            let lCount = try viewContext.count(for: lRequest)
            if lCount != lessonChangeToken { lessonChangeToken = lCount; changed = true }
            let sRequest = CDFetchRequest(CDStudent.self)
            let sCount = try viewContext.count(for: sRequest)
            if sCount != studentChangeToken { studentChangeToken = sCount; changed = true }
        } catch {
            Self.logger.warning("Failed to refresh change tokens: \(error)")
        }
        return changed
    }

    /// Every entity the partition, the quiet-students map, or the change
    /// tokens read: open work and what triages it (check-ins, notes,
    /// participants), presentations and their follow-up rows, the school
    /// calendar behind the school-day counts, and the lesson and student
    /// tables the tokens count. A save touching none of these cannot change
    /// anything this screen derives.
    nonisolated static let agendaEntityNames: Set<String> = [
        "WorkModel", "WorkCheckIn", "Note", "WorkParticipantEntity",
        "LessonAssignment", "LessonPresentation",
        "NonSchoolDay", "SchoolDayOverride",
        "Lesson", "Student"
    ]

    /// True when a `NSManagedObjectContextDidSave` should refresh the screen
    /// (fails open on an unrecognised payload — see
    /// `ManagedObjectChangeScope.saveTouches`).
    nonisolated static func saveTouchesAgenda(_ userInfo: [AnyHashable: Any]?) -> Bool {
        ManagedObjectChangeScope.saveTouches(agendaEntityNames, in: userInfo)
    }

    // MARK: - Triage

    /// Runs after a debounced batch of saves.
    ///
    /// `dataReloadTrigger` only hashes counts, so a save that moves a record
    /// between lists without changing how many there are would not reach the
    /// caches. This is the path that catches it.
    func refreshAfterSave() {
        // A moved token already schedules the reload, which rebuilds the
        // partition; building it here too would triage everything twice.
        if refreshChangeTokens() { return }
        rebuildPartition()
    }

    /// Re-triages everything on screen in one pass.
    ///
    /// Assignments are fetched here rather than held in a `@FetchRequest`
    /// because this runs on a debounced path, and the rule reads only their
    /// `state`, `scheduledFor` and `id` — no relationships to fault. Only the
    /// rows that can land outside `.done` are fetched (see
    /// `LessonsAndWorkPartition.workspaceAssignments`).
    func rebuildPartition() {
        let unresolvedFollowUpIDs = LessonsAndWorkTriage.unresolvedFollowUpAssignmentIDs(in: viewContext)
        let works = Array(openWork).uniqueByID
        workVisibility = WorkVisibility(covering: works, in: viewContext)
        partition = LessonsAndWorkPartition(
            openWork: works,
            assignments: LessonsAndWorkPartition.workspaceAssignments(
                in: viewContext, unresolvedFollowUpIDs: unresolvedFollowUpIDs
            ),
            unresolvedFollowUpIDs: unresolvedFollowUpIDs,
            context: viewContext
        )
        partitionBuiltAt = Date()
        rebuildQuietStudents()
        rebuildBeforeLesson()
    }

    /// The Before a Lesson pill's list: the open earlier work of the children
    /// in the lessons planned for the next three school days, one fetch for
    /// all of them.
    func rebuildBeforeLesson() {
        let days = LessonsAndWorkTriage.beforeLessonDays(from: Date()) { day in
            SchoolDayChecker.isSchoolDay(day, using: viewContext)
        }
        beforeLesson = BeforeLessonWork.build(
            presentations: partition.presentations.scheduled,
            days: days,
            lessons: dependencies.lessonCatalog.all,
            in: viewContext
        )
    }

    /// The Work column's two inputs: how long each child has gone without the
    /// guide looking at anything of theirs, and — by the same map's keys — who
    /// has anything open at all.
    ///
    /// Runs here rather than in a `body` pass for the reason the partition does:
    /// it reads every open item's check-ins and notes and then counts school
    /// days. The steps are the card's own — `lastMeaningfulTouchDate`, then
    /// `SchoolCalendarService` — so a child's row and their cards cannot
    /// disagree about how long something has sat.
    func rebuildQuietStudents() {
        let works = Array(openWork).uniqueByID
        let cache = SchoolCalendarService.shared
        let today = Date()

        let touchDates = works.map { work in
            WorkAgingPolicy.lastMeaningfulTouchDate(
                for: work,
                checkIns: (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? [],
                notes: (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
            )
        }
        // One preload for the whole range, so the school-day count below is a
        // cache hit per item rather than a fetch per item.
        if let earliest = touchDates.min() {
            cache.preloadNonSchoolDays(from: earliest, to: today, using: viewContext)
        }

        var ageByWorkID: [UUID: Int] = [:]
        for (work, touched) in zip(works, touchDates) {
            guard let id = work.id else { continue }
            ageByWorkID[id] = cache.schoolDaysSinceCreation(
                createdAt: touched, asOf: today, using: viewContext
            )
        }

        workAgeByID = ageByWorkID
        quietDaysByStudent = QuietStudentsOrder.daysSinceTouchByStudent(
            in: works, visibility: workVisibility
        ) { work in
            work.id.flatMap { ageByWorkID[$0] } ?? 0
        }
    }

    /// The ids the card badge flags, so a card cannot be marked as needing the
    /// guide while sitting outside the Attention list.
    var attentionWorkIDs: Set<UUID> {
        Set(partition.work.attention.compactMap(\.id))
    }

    /// Children who already have a lesson coming up.
    ///
    /// Derived from the partition's scheduled presentations, which is a
    /// superset — it also holds lessons whose day has passed without being
    /// given, and those children still need planning. Built here, once per
    /// refresh, because a student's assignments are a JSON blob with no
    /// queryable relationship: asking per row means decoding every assignment
    /// per row.
    var studentIDsWithUpcomingLessons: Set<UUID> {
        WaitingStudentsOrder.studentIDsWithUpcomingLessons(in: partition.presentations.scheduled)
    }

    // MARK: - Cache Loading

    func loadLessonsAndStudentsIfNeeded() {
        // Collect IDs from open work
        var neededLessonIDs = Set<UUID>()
        var neededStudentIDs = Set<UUID>()

        for work in openWork {
            if let lid = UUID(uuidString: work.lessonID) {
                neededLessonIDs.insert(lid)
            }
            if let sid = UUID(uuidString: work.studentID) {
                neededStudentIDs.insert(sid)
            }
        }

        // Load only needed lessons, from the shared catalog (already keyed by
        // id, CloudKit duplicates dropped first-wins) rather than a fresh
        // whole-table fetch.
        if !neededLessonIDs.isEmpty {
            let catalog = dependencies.lessonCatalog.byID
            lessonsByIDCache = catalog.filter { neededLessonIDs.contains($0.key) }
        } else {
            lessonsByIDCache = [:]
        }

        // The card cache needs only the owners on screen, withdrawn children
        // included so a shared row they own still has a name on it. (The Work
        // column reads the whole enrolled roster live: `rosterStudents`.)
        let allStudents: [CDStudent] = dependencies.roster.all

        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let filtered = allStudents.filter { neededStudentIDs.contains($0.id ?? UUID()) }
            let visible = TestStudentsFilter.filterVisible(
                filtered, show: testStudents.show,
                namesRaw: testStudents.namesRaw
            ).uniqueByID
            studentsByIDCache = Dictionary(
                visible.compactMap { guard let id = $0.id else { return nil }; return (id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            studentsByIDCache = [:]
        }

        // Triage rides the same debounced path as the caches above.
        rebuildPartition()
    }

    // MARK: - Data Helpers

    /// The enrolled roster less hidden test students: the Work column's
    /// children, everyone the guide is teaching including those with nothing,
    /// and the children whose work the grid shows. Read live from the shared
    /// roster, which observation keeps current, so a child who leaves goes from
    /// the column at once; it used to be copied only when the number of
    /// students changed.
    var rosterStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        ).uniqueByID
    }

    /// Everything the search field and the kind chips leave visible, whichever
    /// pill is selected. The Work half slices the triaged partition against
    /// this, so text and kind are filtered in exactly one place.
    var visibleWorkIDs: Set<UUID> {
        Set(openWorksFiltered().compactMap(\.id))
    }

    /// The work actually on screen: the selected pill's slice of the partition,
    /// narrowed to what the filters left. This is what gets printed, so the
    /// sheet matches the list the guide is looking at.
    func worksOnScreen() -> [CDWorkModel] {
        let visible = visibleWorkIDs
        if workChip == .beforeLesson { return beforeLesson.works(visibleTo: visible) }
        return workChip.slice(of: partition.work).filter { work in
            guard let id = work.id else { return false }
            return visible.contains(id)
        }
    }

    func openWorksFiltered() -> [CDWorkModel] {
        // Filter open work in memory (anything with an open status). The
        // column's child filter is applied here with the rest so the pill
        // counts and the printed sheet see the list the guide is looking at.
        let filter = WorkAgendaFilter(
            hideScheduled: hideScheduled,
            chip: workChip,
            kinds: visibleKinds.wrappedValue,
            studentID: workStudentFilter,
            rosterIDs: Set(rosterStudents.compactMap(\.id))
        )
        var works = filter.apply(
            to: Array(openWork).uniqueByID, partition: partition, visibility: workVisibility
        )

        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(w.title)
                hay.append(lessonTitle(for: w))
                hay.append(w.displayKind.displayName)
                if let s = studentsByID[uuidString: w.studentID] {
                    hay.append(s.firstName)
                    hay.append(s.lastName)
                    hay.append(s.fullName)
                    hay.append(s.shortName)
                }
                return hay.joined(separator: " ").lowercased().contains(query)
            }
        }
        return works
    }

    func lessonTitle(for work: CDWorkModel) -> String {
        let name = lessonsByID[uuidString: work.lessonID]?.name
        return LessonFormatter.lessonName(name, orRowTitle: work.title, missing: LessonFormatter.untitledWork)
    }

    #if os(macOS)
    func makePrintItems(from works: [CDWorkModel]) -> [WorkPDFRenderer.PrintItem] {
        works.map { w in
            let title = lessonTitle(for: w)
            let student = (UUID(uuidString: w.studentID))
                .flatMap { studentsByID[$0] }
                .map(\.shortName) ?? "Student"
            return WorkPDFRenderer.PrintItem(
                id: w.id ?? UUID(),
                lessonTitle: title,
                studentName: student,
                statusLabel: statusLabel(for: w),
                // The card's own number: school days since last touched. The
                // sheet used to count calendar days since the work was made.
                ageDays: w.id.flatMap { workAgeByID[$0] } ?? 0,
                dueAt: w.dueAt,
                needsAttention: needsAttention(for: w)
            )
        }
    }
    #endif

    func statusLabel(for w: CDWorkModel) -> String {
        w.status.displayName
    }

    /// The printed sheet flags exactly the work the Attention list holds, via
    /// the same `LessonsAndWorkTriage` rule.
    func needsAttention(for w: CDWorkModel) -> Bool {
        LessonsAndWorkTriage.bucket(for: w, context: viewContext) == .attention
    }
}
