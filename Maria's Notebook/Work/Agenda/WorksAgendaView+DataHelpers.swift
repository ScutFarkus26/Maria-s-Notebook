// WorksAgendaView+DataHelpers.swift
// Cache loading, filtering, and display helpers for WorksAgendaView.

import SwiftUI
import CoreData
import OSLog

extension WorksAgendaView {

    // MARK: - Change Detection

    /// PERF: Lightweight change detection using fetchCount() instead of loading full tables.
    func refreshChangeTokens() {
        do {
            let lRequest: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
            let lCount = try viewContext.count(for: lRequest)
            if lCount != lessonChangeToken { lessonChangeToken = lCount }
            let sRequest: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
            let sCount = try viewContext.count(for: sRequest)
            if sCount != studentChangeToken { studentChangeToken = sCount }
        } catch {
            Self.logger.warning("Failed to refresh change tokens: \(error)")
        }
    }

    // MARK: - Triage

    /// Runs after a debounced batch of saves.
    ///
    /// `dataReloadTrigger` only hashes counts, so a save that moves a record
    /// between lists without changing how many there are would not reach the
    /// caches. This is the path that catches it.
    func refreshAfterSave() {
        refreshChangeTokens()
        rebuildPartition()
    }

    /// Re-triages everything on screen in one pass.
    ///
    /// Assignments are fetched here rather than held in a `@FetchRequest`
    /// because this runs on a debounced path, and the rule reads only their
    /// `state`, `scheduledFor` and `id` — no relationships to fault.
    func rebuildPartition() {
        let assignmentRequest: NSFetchRequest<CDLessonAssignment> =
            NSFetchRequest(entityName: "LessonAssignment")
        partition = LessonsAndWorkPartition(
            openWork: Array(openWork).uniqueByID,
            assignments: viewContext.safeFetch(assignmentRequest),
            unresolvedFollowUpIDs: LessonsAndWorkTriage
                .unresolvedFollowUpAssignmentIDs(in: viewContext),
            context: viewContext,
            calendar: calendar
        )
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

        // Load only needed lessons
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededLessonIDs.isEmpty {
            let all: [CDLesson] = viewContext.safeFetch(NSFetchRequest<CDLesson>(entityName: "Lesson"))
            let filtered = all.filter { neededLessonIDs.contains($0.id ?? UUID()) }
            lessonsByIDCache = Dictionary(
                filtered.compactMap { guard let id = $0.id else { return nil }; return (id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            lessonsByIDCache = [:]
        }

        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let all: [CDStudent] = viewContext.safeFetch(NSFetchRequest<CDStudent>(entityName: "Student"))
            let filtered = all.filter { neededStudentIDs.contains($0.id ?? UUID()) }
            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let visible = TestStudentsFilter.filterVisible(
                filtered, show: showTestStudents,
                namesRaw: testStudentNamesRaw
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

    func openWorksFiltered() -> [CDWorkModel] {
        // Filter open work in memory (anything NOT .complete)
        var works = Array(openWork).uniqueByID

        // Hide scheduled work if enabled
        if hideScheduled {
            let scheduledWorkIDs = Set(scheduledCheckIns.compactMap { UUID(uuidString: $0.workID) })
            works = works.filter { !scheduledWorkIDs.contains($0.id ?? UUID()) }
        }

        // Filter by visible work kinds. Untagged work falls back to .practiceLesson,
        // matching how WorkCard displays it.
        let kinds = visibleKinds.wrappedValue
        if kinds.count < WorkKind.allCases.count {
            works = works.filter { kinds.contains($0.kind ?? .practiceLesson) }
        }

        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(w.title)
                hay.append(lessonTitle(forLessonID: w.lessonID))
                hay.append((w.kind ?? .practiceLesson).displayName)
                if let s = studentsByID[uuidString: w.studentID] {
                    hay.append(s.firstName)
                    hay.append(s.lastName)
                    hay.append(s.fullName)
                    hay.append(StudentFormatter.displayName(for: s))
                }
                return hay.joined(separator: " ").lowercased().contains(query)
            }
        }
        return works
    }

    func lessonTitle(forLessonID lessonID: String) -> String {
        let name = lessonsByID[uuidString: lessonID]?.name ?? ""
        return LessonFormatter.titleOrFallback(name, fallback: "Lesson \(String(lessonID.prefix(6)))")
    }

    #if os(macOS)
    func makePrintItems(from works: [CDWorkModel]) -> [WorkPDFRenderer.PrintItem] {
        works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = (UUID(uuidString: w.studentID))
                .flatMap { studentsByID[$0] }
                .map(StudentFormatter.displayName(for:)) ?? "Student"
            return WorkPDFRenderer.PrintItem(
                id: w.id ?? UUID(),
                lessonTitle: title,
                studentName: student,
                statusLabel: statusLabel(for: w),
                ageDays: ageDays(for: w),
                dueAt: w.dueAt,
                needsAttention: needsAttention(for: w)
            )
        }
    }
    #endif

    func statusLabel(for w: CDWorkModel) -> String {
        switch w.status {
        case .active: return "Practice"
        case .review: return "Follow-Up"
        case .complete: return "Completed"
        }
    }

    func ageDays(for w: CDWorkModel) -> Int {
        // Clamped to the school-year counter epoch (see `SchoolYearCounters`).
        let start = AppCalendar.startOfDay(SchoolYearCounters.countFrom(w.createdAt ?? Date()))
        let end = AppCalendar.startOfDay(Date())
        return AppCalendar.shared.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// The printed sheet flags exactly the work the Attention list holds, via
    /// the same `LessonsAndWorkTriage` rule.
    func needsAttention(for w: CDWorkModel) -> Bool {
        LessonsAndWorkTriage.bucket(
            for: w,
            context: viewContext,
            calendar: calendar
        ) == .attention
    }
}
