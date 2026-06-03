// PresentationsViewModel+Filtering.swift
// Filtering, sorting, and "Suggest Next" scoring moved out of the inbox view
// so the new screen header can drive Suggest Next without coupling to the inbox.

import Foundation
import CoreData

extension PresentationsViewModel {

    // MARK: - Lookup dictionaries (rebuilt during `updateAsync`, see PresentationsViewModel.swift)

    var lessonsByID: [UUID: CDLesson] { lessonsByIDCache }
    var studentsByID: [UUID: CDStudent] { studentsByIDCache }

    // MARK: - Title / name helpers

    func lessonTitle(for la: CDLessonAssignment) -> String {
        if let lesson = lessonsByID[uuidString: la.lessonID] {
            let name = lesson.name.trimmed()
            if !name.isEmpty { return name }
        }
        return "Lesson \(String(la.lessonID.prefix(6)))"
    }

    func studentNames(for la: CDLessonAssignment) -> String {
        let lookup = studentsByID
        let names = la.resolvedStudentIDs.compactMap { id -> String? in
            guard let student = lookup[id] else { return nil }
            return StudentFormatter.displayName(for: student)
        }
        return names.joined(separator: ", ")
    }

    // MARK: - Search matching

    func matchesSearch(_ la: CDLessonAssignment, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lessonTitleLower = lessonTitle(for: la).lowercased()
        let studentNamesLower = studentNames(for: la).lowercased()
        let areaLower = (lessonsByID[uuidString: la.lessonID]?.area ?? "").lowercased()
        return lessonTitleLower.contains(query)
            || studentNamesLower.contains(query)
            || areaLower.contains(query)
    }

    // MARK: - Filtering by student + search + committed tokens

    private func applyStudentFilter(
        _ lessons: [CDLessonAssignment],
        studentFilter: UUID?
    ) -> [CDLessonAssignment] {
        guard let studentID = studentFilter else { return lessons }
        let studentIDString = studentID.uuidString
        return lessons.filter { $0.studentIDs.contains(studentIDString) }
    }

    /// Student IDs that appear on any presentation whose `scheduledForDay`
    /// matches today's start-of-day. Used by the "Hide Today's Students" toggle.
    var studentIDsScheduledToday: Set<UUID> {
        let today = calendar.startOfDay(for: Date())
        var ids = Set<UUID>()
        for la in cachedLessonAssignments {
            guard let day = la.scheduledForDay,
                  calendar.isDate(day, inSameDayAs: today) else { continue }
            ids.formUnion(la.resolvedStudentIDs)
        }
        return ids
    }

    private func applyHideScheduledToday(
        _ lessons: [CDLessonAssignment],
        hide: Bool
    ) -> [CDLessonAssignment] {
        guard hide else { return lessons }
        let busy = studentIDsScheduledToday
        guard !busy.isEmpty else { return lessons }
        return lessons.filter { Set($0.resolvedStudentIDs).isDisjoint(with: busy) }
    }

    private func applyTextFilters(
        _ lessons: [CDLessonAssignment],
        debouncedSearch: String,
        committedFilters: [String]
    ) -> [CDLessonAssignment] {
        let liveQuery = debouncedSearch.trimmed().lowercased()
        return lessons.filter { la in
            for token in committedFilters where !matchesSearch(la, query: token) {
                return false
            }
            return matchesSearch(la, query: liveQuery)
        }
    }

    private func sortByAge(_ lessons: [CDLessonAssignment]) -> [CDLessonAssignment] {
        lessons.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Public wrapper: apply student filter + committed-token filter + live search
    /// to an arbitrary slice (e.g. `overdueReady()` or `recentlyMissed()`).
    func applyStudentAndTextFilters(
        to lessons: [CDLessonAssignment],
        studentFilter: UUID?,
        debouncedSearch: String,
        committedFilters: [String],
        hideStudentsScheduledToday: Bool = false
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(lessons, studentFilter: studentFilter)
        let afterText = applyTextFilters(
            afterStudent,
            debouncedSearch: debouncedSearch,
            committedFilters: committedFilters
        )
        return applyHideScheduledToday(afterText, hide: hideStudentsScheduledToday)
    }

    func filteredAndSortedReady(
        studentFilter: UUID?,
        debouncedSearch: String,
        committedFilters: [String],
        hideStudentsScheduledToday: Bool = false
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(readyLessons, studentFilter: studentFilter)
        let afterText = applyTextFilters(
            afterStudent,
            debouncedSearch: debouncedSearch,
            committedFilters: committedFilters
        )
        let afterToday = applyHideScheduledToday(afterText, hide: hideStudentsScheduledToday)
        return sortByAge(afterToday)
    }

    func filteredAndSortedBlocked(
        studentFilter: UUID?,
        debouncedSearch: String,
        committedFilters: [String],
        hideStudentsScheduledToday: Bool = false
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(blockedLessons, studentFilter: studentFilter)
        let afterText = applyTextFilters(
            afterStudent,
            debouncedSearch: debouncedSearch,
            committedFilters: committedFilters
        )
        let afterToday = applyHideScheduledToday(afterText, hide: hideStudentsScheduledToday)
        return sortByAge(afterToday)
    }

    // MARK: - Suggest Next

    /// CDStudent IDs that already have a scheduled (but not yet given) lesson.
    private func scheduledStudentIDs(in lessonAssignments: [CDLessonAssignment]) -> Set<UUID> {
        var ids = Set<UUID>()
        for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
            ids.formUnion(la.resolvedStudentIDs)
        }
        return ids
    }

    private func suggestScore(
        for la: CDLessonAssignment,
        scheduledStudentIDs scheduled: Set<UUID>
    ) -> Double {
        // Factor 1: Max days since last lesson, only counting students who
        // don't already have a scheduled lesson.
        let relevantStudents = la.resolvedStudentIDs.filter { !scheduled.contains($0) }
        let maxStudentDays = relevantStudents
            .compactMap { daysSinceLastLessonByStudent[$0] }
            .max() ?? 0
        let studentScore = Double(min(maxStudentDays, 999))

        // Factor 2: Lesson age in inbox (school days, not calendar days).
        let ageInSchoolDays: Double
        if let viewContext {
            ageInSchoolDays = Double(LessonAgeHelper.schoolDaysSinceCreation(
                createdAt: la.createdAt ?? Date(), asOf: Date(),
                using: viewContext, calendar: calendar
            ))
        } else {
            ageInSchoolDays = 0
        }

        // Factor 3: Open work — boost lessons for students with less open work.
        let minOpenWork = relevantStudents
            .map { openWorkCountByStudent[$0] ?? 0 }
            .min() ?? 0
        let openWorkBoost = max(0.0, 20.0 - Double(minOpenWork) * 5.0)

        // Factor 4: Area diversity — penalize repeating last area.
        let lessonArea = lessonsByID[la.resolvedLessonID]?.area
            .trimmed().lowercased() ?? ""
        var diversityPenalty = 0.0
        if !lessonArea.isEmpty {
            for sid in relevantStudents where lastAreaByStudent[sid]?.trimmed().lowercased() == lessonArea {
                diversityPenalty += 5.0
            }
        }

        return studentScore * 10.0 + ageInSchoolDays + openWorkBoost - diversityPenalty
    }

    /// Picks the highest-priority ready lesson among `candidates`.
    /// `allLessonAssignments` is used to compute which students already have a scheduled lesson.
    func suggestedNext(
        among candidates: [CDLessonAssignment],
        allLessonAssignments: [CDLessonAssignment]
    ) -> CDLessonAssignment? {
        guard !candidates.isEmpty else { return nil }
        let scheduled = scheduledStudentIDs(in: allLessonAssignments)
        return candidates.max { a, b in
            suggestScore(for: a, scheduledStudentIDs: scheduled)
                < suggestScore(for: b, scheduledStudentIDs: scheduled)
        }
    }

    /// Top-N suggested ready lessons (used by the Suggested Next chip).
    func suggestedNextLessons(
        among candidates: [CDLessonAssignment],
        allLessonAssignments: [CDLessonAssignment],
        limit: Int = 3
    ) -> [CDLessonAssignment] {
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let scheduled = scheduledStudentIDs(in: allLessonAssignments)
        let ranked = candidates.sorted {
            suggestScore(for: $0, scheduledStudentIDs: scheduled)
                > suggestScore(for: $1, scheduledStudentIDs: scheduled)
        }
        return Array(ranked.prefix(limit))
    }

    // MARK: - Overdue + Recently Missed slices

    /// Ready lessons whose age in school days exceeds the threshold.
    /// Defaults to 14 — see the redesign spec.
    func overdueReady(thresholdSchoolDays: Int = 14) -> [CDLessonAssignment] {
        guard let viewContext else { return [] }
        return readyLessons.filter { la in
            let age = LessonAgeHelper.schoolDaysSinceCreation(
                createdAt: la.createdAt ?? Date(),
                asOf: Date(),
                using: viewContext,
                calendar: calendar
            )
            return age > thresholdSchoolDays
        }
    }

    /// Presentations scheduled in the last `daysBack` days where at least one
    /// assigned student was absent on `scheduledForDay` and the presentation
    /// has not been given. Uses one batched attendance fetch per affected day.
    func recentlyMissed(within daysBack: Int = 14) -> [CDLessonAssignment] {
        guard let viewContext else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        let candidates = cachedLessonAssignments.filter { la in
            guard !la.isGiven, let scheduledDay = la.scheduledForDay else { return false }
            let day = calendar.startOfDay(for: scheduledDay)
            return day >= cutoff && day <= today
        }
        guard !candidates.isEmpty else { return [] }

        let grouped = Dictionary(grouping: candidates) { la -> Date in
            calendar.startOfDay(for: la.scheduledForDay ?? Date())
        }

        var missed: [CDLessonAssignment] = []
        for (day, las) in grouped {
            let studentIDs = Array(Set(las.flatMap { $0.resolvedStudentIDs }))
            let statuses = viewContext.attendanceStatuses(for: studentIDs, on: day)
            for la in las where la.resolvedStudentIDs.contains(where: { statuses[$0] == .absent }) {
                missed.append(la)
            }
        }
        return missed
    }
}
