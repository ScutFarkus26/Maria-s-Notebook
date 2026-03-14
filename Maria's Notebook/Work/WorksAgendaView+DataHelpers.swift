// WorksAgendaView+DataHelpers.swift
// Cache loading, filtering, and display helpers for WorksAgendaView.

import SwiftUI
import SwiftData
import OSLog

extension WorksAgendaView {

    // MARK: - Change Detection

    /// PERF: Lightweight change detection using fetchCount() instead of loading full tables.
    func refreshChangeTokens() {
        do {
            let lCount = try modelContext.fetchCount(FetchDescriptor<Lesson>())
            if lCount != lessonChangeToken { lessonChangeToken = lCount }
            let sCount = try modelContext.fetchCount(FetchDescriptor<Student>())
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
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededLessonIDs.isEmpty {
            let all: [Lesson]
            do {
                all = try modelContext.fetch(FetchDescriptor<Lesson>())
            } catch {
                Self.logger.warning("Failed to fetch lessons: \(error)")
                all = []
            }
            let filtered = all.filter { neededLessonIDs.contains($0.id) }
            lessonsByIDCache = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            lessonsByIDCache = [:]
        }

        // Load only needed students
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        // Use uniquingKeysWith to handle CloudKit sync duplicates
        if !neededStudentIDs.isEmpty {
            let all: [Student]
            do {
                all = try modelContext.fetch(FetchDescriptor<Student>())
            } catch {
                Self.logger.warning("Failed to fetch students: \(error)")
                all = []
            }
            let filtered = all.filter { neededStudentIDs.contains($0.id) }
            // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
            let visible = TestStudentsFilter.filterVisible(
                filtered, show: showTestStudents,
                namesRaw: testStudentNamesRaw
            ).uniqueByID
            studentsByIDCache = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            studentsByIDCache = [:]
        }
    }

    // MARK: - Data Helpers

    func openWorksFiltered() -> [WorkModel] {
        // Filter open work in memory (anything NOT .complete)
        var works = openWork

        // Hide scheduled work if enabled
        if hideScheduled {
            let scheduledWorkIDs = Set(scheduledCheckIns.compactMap { UUID(uuidString: $0.workID) })
            works = works.filter { !scheduledWorkIDs.contains($0.id) }
        }

        // Optional search (use debounced text for filtering)
        if !debouncedSearchText.trimmed().isEmpty {
            let query = debouncedSearchText.lowercased()
            works = works.filter { w in
                var hay: [String] = []
                hay.append(lessonTitle(forLessonID: w.lessonID))
                if let sid = UUID(uuidString: w.studentID), let s = studentsByID[sid] {
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
        if let lid = UUID(uuidString: lessonID), let lesson = lessonsByID[lid] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(lessonID.prefix(6)))"
    }

    #if os(macOS)
    func makePrintItems(from works: [WorkModel]) -> [WorkPDFRenderer.PrintItem] {
        works.map { w in
            let title = lessonTitle(forLessonID: w.lessonID)
            let student = (UUID(uuidString: w.studentID))
                .flatMap { studentsByID[$0] }
                .map(studentPrintName(for:)) ?? "Student"
            return WorkPDFRenderer.PrintItem(
                id: w.id,
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

    func studentPrintName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    func statusLabel(for w: WorkModel) -> String {
        switch w.status {
        case .active: return "Practice"
        case .review: return "Follow-Up"
        case .complete: return "Completed"
        }
    }

    func ageDays(for w: WorkModel) -> Int {
        let start = AppCalendar.startOfDay(w.createdAt)
        let end = AppCalendar.startOfDay(Date())
        return AppCalendar.shared.dateComponents([.day], from: start, to: end).day ?? 0
    }

    func needsAttention(for w: WorkModel) -> Bool {
        if let due = w.dueAt,
           AppCalendar.startOfDay(due) < AppCalendar.startOfDay(Date()) {
            return true
        }
        if let lastNoteDate = (w.unifiedNotes ?? [])
            .map({ max($0.updatedAt, $0.createdAt) }).max() {
            let days = AppCalendar.shared.dateComponents(
                [.day],
                from: AppCalendar.startOfDay(lastNoteDate),
                to: AppCalendar.startOfDay(Date())
            ).day ?? 0
            if days >= 10 { return true }
        }
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: w.createdAt, asOf: Date(),
            using: modelContext, calendar: calendar
        ) >= 10
    }
}
