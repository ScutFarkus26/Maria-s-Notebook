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

    private func applyTextFilters(
        _ lessons: [CDLessonAssignment],
        debouncedSearch: String
    ) -> [CDLessonAssignment] {
        let liveQuery = debouncedSearch.trimmed().lowercased()
        return lessons.filter { matchesSearch($0, query: liveQuery) }
    }

    private func sortByAge(_ lessons: [CDLessonAssignment]) -> [CDLessonAssignment] {
        lessons.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Public wrapper: apply student filter + live search to an arbitrary slice
    /// (e.g. `overdueReady()` or `recentlyMissed()`).
    func applyStudentAndTextFilters(
        to lessons: [CDLessonAssignment],
        studentFilter: UUID?,
        debouncedSearch: String
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(lessons, studentFilter: studentFilter)
        return applyTextFilters(afterStudent, debouncedSearch: debouncedSearch)
    }

    func filteredAndSortedReady(
        studentFilter: UUID?,
        debouncedSearch: String
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(readyLessons, studentFilter: studentFilter)
        let afterText = applyTextFilters(afterStudent, debouncedSearch: debouncedSearch)
        return sortByAge(afterText)
    }

    func filteredAndSortedBlocked(
        studentFilter: UUID?,
        debouncedSearch: String
    ) -> [CDLessonAssignment] {
        let afterStudent = applyStudentFilter(blockedLessons, studentFilter: studentFilter)
        let afterText = applyTextFilters(afterStudent, debouncedSearch: debouncedSearch)
        return sortByAge(afterText)
    }

    // MARK: - Suggest Next

    /// How many picks the Suggested Next pill offers. Five is a morning's worth
    /// of choices — enough that the guide is choosing rather than being told,
    /// while still fitting two rows of the three-wide grid.
    static let suggestedNextLimit = 5

    /// CDStudent IDs that already have a scheduled (but not yet given) lesson.
    private func scheduledStudentIDs(in lessonAssignments: [CDLessonAssignment]) -> Set<UUID> {
        var ids = Set<UUID>()
        for la in lessonAssignments where la.scheduledFor != nil && !la.isGiven {
            ids.formUnion(la.resolvedStudentIDs)
        }
        return ids
    }

    /// Every input to one card's rank, gathered once. The score and the
    /// sentence under the card both read from this, so they cannot drift.
    private struct SuggestFactors {
        /// Longest-waiting child not already booked, and their wait in school
        /// days — `nil` days means never taught.
        var longestWaiting: (id: UUID, days: Int?)?
        /// True when every child on the card is already booked for something.
        var everyoneAlreadyScheduled: Bool
        /// The wait that feeds the score, capped the way it always has been.
        var cappedWait: Double
        var ageInSchoolDays: Double
        /// Fewest open work items among the children who still need something.
        var fewestOpenWork: Int?
        var diversityPenalty: Double
        /// The lesson's area differs from what all of those children last had.
        var changesArea: Bool

        var score: Double {
            let openWorkBoost = max(0.0, 20.0 - Double(fewestOpenWork ?? 0) * 5.0)
            return cappedWait * 10.0 + ageInSchoolDays + openWorkBoost - diversityPenalty
        }
    }

    private func suggestFactors(
        for la: CDLessonAssignment,
        scheduledStudentIDs scheduled: Set<UUID>
    ) -> SuggestFactors {
        // Factor 1: Longest wait since a lesson, only counting students who
        // don't already have a scheduled lesson.
        let relevantStudents = la.resolvedStudentIDs.filter { !scheduled.contains($0) }
        let waits = relevantStudents.compactMap { sid -> (UUID, Int)? in
            guard let days = daysSinceLastLessonByStudent[sid] else { return nil }
            return (sid, days)
        }
        let longest = waits.max { $0.1 < $1.1 }
        // A never-taught child is stored as `Int.max`; the score caps it, the
        // sentence names them instead of printing an absurd number of days.
        var longestWaiting: (id: UUID, days: Int?)?
        if let longest {
            longestWaiting = (id: longest.0, days: longest.1 == Int.max ? nil : longest.1)
        }
        let cappedWait = Double(min(longest?.1 ?? 0, 999))

        // Factor 2: Lesson age in inbox (school days, not calendar days).
        let ageInSchoolDays: Double
        if let viewContext {
            ageInSchoolDays = Double(LessonAgeHelper.schoolDaysSinceCreation(
                createdAt: la.createdAt ?? Date(), asOf: Date(),
                using: viewContext
            ))
        } else {
            ageInSchoolDays = 0
        }

        // Factor 3: Open work — boost lessons for students with less open work.
        let fewestOpenWork = relevantStudents
            .map { openWorkCountByStudent[$0] ?? 0 }
            .min()

        // Factor 4: Area diversity — penalize repeating last area.
        let lessonArea = lessonsByID[la.resolvedLessonID]?.area
            .trimmed().lowercased() ?? ""
        var diversityPenalty = 0.0
        var anyKnownLastArea = false
        if !lessonArea.isEmpty {
            for sid in relevantStudents {
                guard let last = lastAreaByStudent[sid]?.trimmed().lowercased(),
                      !last.isEmpty else { continue }
                anyKnownLastArea = true
                if last == lessonArea { diversityPenalty += 5.0 }
            }
        }

        return SuggestFactors(
            longestWaiting: longestWaiting,
            everyoneAlreadyScheduled: !la.resolvedStudentIDs.isEmpty && relevantStudents.isEmpty,
            cappedWait: cappedWait,
            ageInSchoolDays: ageInSchoolDays,
            fewestOpenWork: fewestOpenWork,
            diversityPenalty: diversityPenalty,
            // Only a real change: with no recorded last area there is nothing
            // to have changed from, and claiming one would be an invention.
            changesArea: anyKnownLastArea && diversityPenalty == 0
        )
    }

    private func rationale(from factors: SuggestFactors) -> SuggestionRationale {
        SuggestionRationale(
            waitingChild: factors.longestWaiting.flatMap { waiting in
                studentsByID[waiting.id].map { StudentFormatter.displayName(for: $0) }
            },
            waitingSchoolDays: factors.longestWaiting?.days,
            everyoneAlreadyScheduled: factors.everyoneAlreadyScheduled,
            inboxSchoolDays: Int(factors.ageInSchoolDays),
            fewestOpenWork: factors.fewestOpenWork,
            changesArea: factors.changesArea
        )
    }

    /// The top `limit` ready lessons, each carrying why it was picked.
    /// `allLessonAssignments` is used to compute which students already have a
    /// scheduled lesson.
    func rankedSuggestions(
        among candidates: [CDLessonAssignment],
        allLessonAssignments: [CDLessonAssignment],
        limit: Int = PresentationsViewModel.suggestedNextLimit
    ) -> [SuggestedPresentation] {
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let scheduled = scheduledStudentIDs(in: allLessonAssignments)
        // Score once per candidate rather than once per comparison — the age
        // factor walks the school calendar, and a sort would re-walk it.
        let scored = candidates.map { la in
            (assignment: la, factors: suggestFactors(for: la, scheduledStudentIDs: scheduled))
        }
        return scored
            .sorted { $0.factors.score > $1.factors.score }
            .prefix(limit)
            .map { SuggestedPresentation(assignment: $0.assignment, rationale: rationale(from: $0.factors)) }
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
                using: viewContext
            )
            return age > thresholdSchoolDays
        }
    }

    /// Presentations scheduled in the last `daysBack` days where at least one
    /// assigned student was absent on its scheduled day and the presentation
    /// has not been given. Uses one batched attendance fetch per affected day.
    func recentlyMissed(within daysBack: Int = 14) -> [CDLessonAssignment] {
        guard let viewContext else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return [] }

        let candidates = cachedLessonAssignments.filter { la in
            guard !la.isGiven, let scheduledDay = la.scheduledFor else { return false }
            let day = calendar.startOfDay(for: scheduledDay)
            return day >= cutoff && day <= today
        }
        guard !candidates.isEmpty else { return [] }

        let grouped = Dictionary(grouping: candidates) { la -> Date in
            calendar.startOfDay(for: la.scheduledFor ?? Date())
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
