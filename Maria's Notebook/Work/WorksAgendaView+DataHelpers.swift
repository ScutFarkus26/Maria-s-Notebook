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
            let all: [Lesson] = viewContext.safeFetch(NSFetchRequest<CDLesson>(entityName: "Lesson"))
            let filtered = all.filter { neededLessonIDs.contains($0.id ?? UUID()) }
            lessonsByIDCache = Dictionary(filtered.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            lessonsByIDCache = [:]
        }

        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let all: [Student] = viewContext.safeFetch(NSFetchRequest<CDStudent>(entityName: "Student"))
            let filtered = all.filter { neededStudentIDs.contains($0.id ?? UUID()) }
            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let visible = TestStudentsFilter.filterVisible(
                filtered, show: showTestStudents,
                namesRaw: testStudentNamesRaw
            ).uniqueByID
            studentsByIDCache = Dictionary(visible.compactMap { guard let id = $0.id else { return nil }; return (id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            studentsByIDCache = [:]
        }
    }

    // MARK: - Data Helpers

    func openWorksFiltered() -> [WorkModel] {
        // Filter open work in memory (anything NOT .complete)
        var works = Array(openWork)

        // Hide scheduled work if enabled
        if hideScheduled {
            let scheduledWorkIDs = Set(scheduledCheckIns.compactMap { UUID(uuidString: $0.workID) })
            works = works.filter { !scheduledWorkIDs.contains($0.id ?? UUID()) }
        }

        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(lessonTitle(forLessonID: w.lessonID))
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
    func makePrintItems(from works: [WorkModel]) -> [WorkPDFRenderer.PrintItem] {
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

    func statusLabel(for w: WorkModel) -> String {
        switch w.status {
        case .active: return "Practice"
        case .review: return "Follow-Up"
        case .complete: return "Completed"
        }
    }

    func ageDays(for w: WorkModel) -> Int {
        let start = AppCalendar.startOfDay(w.createdAt ?? Date())
        let end = AppCalendar.startOfDay(Date())
        return AppCalendar.shared.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func needsAttention(for w: WorkModel) -> Bool {
        if let due = w.dueAt,
           AppCalendar.startOfDay(due) < AppCalendar.startOfDay(Date()) {
            return true
        }
        if let lastNoteDate = ((w.unifiedNotes?.allObjects as? [CDNote]) ?? [])
            .map({ max($0.updatedAt ?? Date.distantPast, $0.createdAt ?? Date.distantPast) }).max() {
            let days = AppCalendar.shared.dateComponents(
                [.day],
                from: AppCalendar.startOfDay(lastNoteDate),
                to: AppCalendar.startOfDay(Date())
            ).day ?? 0
            if days >= 10 { return true }
        }
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: w.createdAt ?? Date(), asOf: Date(),
            using: viewContext, calendar: calendar
        ) >= 10
    }
}
