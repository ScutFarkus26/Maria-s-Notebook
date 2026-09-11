// CurriculumMapEngine.swift
// The pure core of the Three-Year View. Value types in, value types out, no
// fetches — mirroring RecallFrontierEngine and BlockingAlgorithmEngine — so
// every rule about what a glyph means is pinned by CurriculumMapEngineTests.
//
// Rules, from the spec:
//   not presented  no presentation and no mastery record
//   presented      a presentation exists
//   chosen         ≥1 work item or practice session followed the lesson
//   repeated       ≥3 practice sessions, or work moved to review / complete
//   mastered       the mastery record says so, or the guide confirmed
//                  proficiency on the presentation
//   recall         the latest recall-check outcome, drawn as a ring
// The grid reports presence and absence of records. It never judges.

import Foundation

nonisolated enum CurriculumMapEngine {

    // MARK: - Ordering

    /// Taught order within a sequence: `orderInSequence`, then the area-wide
    /// `sortIndex`, then name — the sort every sequence-level screen uses.
    static func precedes(_ lhs: CurriculumLessonRef, _ rhs: CurriculumLessonRef) -> Bool {
        if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Area and sequence names compare the way the Lessons screens compare
    /// them: trimmed and case-insensitive.
    static func filingKey(_ name: String) -> String {
        name.trimmed().lowercased()
    }

    static func sequenceKey(area: String, sequence: String) -> String {
        filingKey(area) + "|" + filingKey(sequence)
    }

    // MARK: - Key Lessons

    /// The first lesson of every sequence — "the first step of every track" —
    /// which counts as a milestone whether or not the guide marked it.
    static func firstLessonIDs(in lessons: [CurriculumLessonRef]) -> Set<UUID> {
        var firstBySequence: [String: CurriculumLessonRef] = [:]
        for lesson in lessons where !lesson.sequence.trimmed().isEmpty {
            let key = sequenceKey(area: lesson.area, sequence: lesson.sequence)
            if let current = firstBySequence[key], !precedes(lesson, current) { continue }
            firstBySequence[key] = lesson
        }
        return Set(firstBySequence.values.map(\.id))
    }

    /// Hand-marked, first in its sequence, or a Great Lesson story.
    static func isKeyLesson(_ lesson: CurriculumLessonRef, firstLessonIDs: Set<UUID>) -> Bool {
        lesson.isKeyLesson
            || firstLessonIDs.contains(lesson.id)
            || (lesson.greatLessonRaw != nil && lesson.isStory)
    }

    /// The lessons a grid shows at a granularity. `.area` returns every lesson,
    /// since the area rows still aggregate over all of them.
    static func lessons(
        _ lessons: [CurriculumLessonRef], at granularity: CurriculumGranularity
    ) -> [CurriculumLessonRef] {
        guard granularity == .keyLessons else { return lessons }
        let first = firstLessonIDs(in: lessons)
        return lessons.filter { isKeyLesson($0, firstLessonIDs: first) }
    }

    // MARK: - Great Lessons

    /// The lessons that stand for each Great Lesson, keyed by `GreatLesson`
    /// raw value: those tagged with it, narrowed to story-format lessons when
    /// any are tagged so a tag on an ordinary follow-up lesson does not stand
    /// in for the story itself. No name matching — an untagged story is simply
    /// absent, and the row says so.
    static func greatLessonLessons(in lessons: [CurriculumLessonRef]) -> [String: [CurriculumLessonRef]] {
        var tagged: [String: [CurriculumLessonRef]] = [:]
        for lesson in lessons {
            guard let raw = lesson.greatLessonRaw, !raw.isEmpty else { continue }
            tagged[raw, default: []].append(lesson)
        }
        return tagged.mapValues { group in
            let stories = group.filter(\.isStory)
            return (stories.isEmpty ? group : stories).sorted(by: precedes)
        }
    }

    // MARK: - Cells

    /// Cells for every child, keyed student → lesson. Only (child, lesson)
    /// pairs with at least one record get a cell; a missing cell is
    /// `.notPresented`, which is the common case and not worth materialising.
    static func cells(input: CurriculumMapInput) -> [UUID: [UUID: CurriculumCell]] {
        builders(input: input, only: nil).mapValues { byLesson in
            byLesson.reduce(into: [UUID: CurriculumCell]()) { cells, entry in
                cells[entry.key] = finalize(entry.value)
            }
        }
    }

    /// Cells for one child, keyed by lesson.
    static func cells(for studentID: UUID, input: CurriculumMapInput) -> [UUID: CurriculumCell] {
        let byLesson = builders(input: input, only: studentID)[studentID] ?? [:]
        return byLesson.reduce(into: [UUID: CurriculumCell]()) { cells, entry in
            cells[entry.key] = finalize(entry.value)
        }
    }

    /// Folds a row's cells: the best state, the latest dates, every event.
    static func aggregate(_ cells: [CurriculumCell], lessonCount: Int) -> CurriculumAggregate {
        var result = CurriculumAggregate()
        result.lessonCount = lessonCount
        var latestRecall: (Date, RecallOutcome)?
        for cell in cells {
            result.state = max(result.state, cell.state)
            if cell.state >= .presented { result.presentedCount += 1 }
            result.firstPresented = earliest(result.firstPresented, cell.firstPresented)
            result.lastPresented = latest(result.lastPresented, cell.lastPresented)
            result.lastActivity = latest(result.lastActivity, cell.lastActivity)
            result.events.append(contentsOf: cell.events)
            for event in cell.events where event.kind == .recall {
                guard let outcome = event.recall else { continue }
                if latestRecall == nil || event.date > latestRecall!.0 { latestRecall = (event.date, outcome) }
            }
        }
        result.recall = latestRecall?.1
        return result
    }

    /// The spec's untouched rule: no presentation in the area for `days` days.
    /// A never-presented area is untouched too — that is the point.
    static func isUntouched(lastPresented: Date?, days: Int, today: Date, calendar: Calendar) -> Bool {
        guard let lastPresented else { return true }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: today)) ?? today
        return lastPresented < cutoff
    }

    // MARK: - Building

    private struct CellBuilder {
        let studentID: UUID
        let lessonID: UUID
        var presentations: [CurriculumPresentationRef] = []
        var mastery: CurriculumMasteryRef?
        var works: [CurriculumWorkRef] = []
        var practice: [CurriculumPracticeRef] = []
        var recalls: [CurriculumRecallRef] = []
    }

    /// One pass over every record, bucketing by (child, lesson). Practice
    /// sessions reach a lesson through the work items they touched; a session
    /// counts for every child in it, on every lesson those items belong to.
    private static func builders(
        input: CurriculumMapInput, only studentID: UUID?
    ) -> [UUID: [UUID: CellBuilder]] {
        var byStudent: [UUID: [UUID: CellBuilder]] = [:]
        func update(_ student: UUID, _ lesson: UUID, _ body: (inout CellBuilder) -> Void) {
            if let studentID, studentID != student { return }
            body(&byStudent[student, default: [:]][lesson, default: CellBuilder(studentID: student, lessonID: lesson)])
        }

        for presentation in input.presentations {
            for student in presentation.studentIDs {
                update(student, presentation.lessonID) { $0.presentations.append(presentation) }
            }
        }
        for mastery in input.masteries {
            update(mastery.studentID, mastery.lessonID) { builder in
                builder.mastery = stronger(builder.mastery, mastery)
            }
        }
        for work in input.work {
            for student in Set(work.studentIDs) {
                update(student, work.lessonID) { $0.works.append(work) }
            }
        }
        let lessonByWork: [UUID: UUID] = Dictionary(
            input.work.map { ($0.id, $0.lessonID) }, uniquingKeysWith: { first, _ in first }
        )
        for session in input.practice {
            let lessons = Set(session.workIDs.compactMap { lessonByWork[$0] })
            for lesson in lessons {
                for student in Set(session.studentIDs) {
                    update(student, lesson) { $0.practice.append(session) }
                }
            }
        }
        for recall in input.recalls {
            update(recall.studentID, recall.lessonID) { $0.recalls.append(recall) }
        }
        return byStudent
    }

    /// CloudKit can leave two mastery rows for one pair; keep the one that
    /// says more.
    private static func stronger(
        _ current: CurriculumMasteryRef?, _ candidate: CurriculumMasteryRef
    ) -> CurriculumMasteryRef {
        guard let current else { return candidate }
        if current.isMastered != candidate.isMastered { return current.isMastered ? current : candidate }
        let candidateSeen = candidate.lastObservedAt ?? .distantPast
        let currentSeen = current.lastObservedAt ?? .distantPast
        return candidateSeen > currentSeen ? candidate : current
    }

    private static func finalize(_ builder: CellBuilder) -> CurriculumCell {
        var cell = CurriculumCell(studentID: builder.studentID, lessonID: builder.lessonID)
        let confirmed = builder.presentations.contains { $0.confirmedStudentIDs.contains(builder.studentID) }
        let isPresented = !builder.presentations.isEmpty || builder.mastery != nil
        let isChosen = !builder.works.isEmpty || !builder.practice.isEmpty
        let isRepeated = builder.practice.count >= 3 || builder.works.contains(where: \.isBeyondActive)
        // Confirmation ("ready for the next lesson", set at capture) is evidence
        // for the mastery sweep, not a mastery mark: only the record's own
        // mark climbs the ladder. The track resolver reads it the same way.
        let isMastered = builder.mastery?.isMastered == true

        if isMastered {
            cell.state = .mastered
        } else if isRepeated {
            cell.state = .repeated
        } else if isChosen {
            cell.state = .chosen
        } else if isPresented {
            cell.state = .presented
        }

        cell.isConfirmed = confirmed
        cell.practiceCount = builder.practice.count
        cell.evidence = CurriculumEvidence(
            presentationIDs: builder.presentations.map(\.id),
            masteryRecordIDs: builder.mastery.map { [$0.id] } ?? [],
            workIDs: builder.works.map(\.id),
            practiceSessionIDs: builder.practice.map(\.id),
            recallCheckIDs: builder.recalls.map(\.id)
        )
        cell.events = events(for: builder).sorted { $0.date < $1.date }

        var presentedDates = builder.presentations.compactMap(\.presentedAt)
        if let masteryPresented = builder.mastery?.presentedAt { presentedDates.append(masteryPresented) }
        cell.firstPresented = presentedDates.min()
        cell.lastPresented = presentedDates.max()
        cell.recall = builder.recalls
            .max { ($0.checkedAt ?? .distantPast) < ($1.checkedAt ?? .distantPast) }?
            .outcome
        let touches = cell.events.map(\.date)
            + [builder.mastery?.lastObservedAt].compactMap { $0 }
            + builder.works.compactMap(\.lastTouchedAt)
        cell.lastActivity = touches.max()
        return cell
    }

    private static func events(for builder: CellBuilder) -> [CurriculumEvent] {
        var events: [CurriculumEvent] = []
        for presentation in builder.presentations {
            guard let date = presentation.presentedAt else { continue }
            events.append(CurriculumEvent(
                date: date, kind: .presentation, state: .presented,
                recall: nil, recordID: presentation.id
            ))
        }
        for work in builder.works {
            if let assigned = work.assignedAt {
                events.append(CurriculumEvent(
                    date: assigned, kind: .work, state: .chosen, recall: nil, recordID: work.id
                ))
            }
            if work.isBeyondActive, let date = work.completedAt ?? work.lastTouchedAt ?? work.assignedAt {
                events.append(CurriculumEvent(
                    date: date, kind: .work, state: .repeated, recall: nil, recordID: work.id
                ))
            }
        }
        let sessions = builder.practice
            .filter { $0.date != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        for (index, session) in sessions.enumerated() {
            guard let date = session.date else { continue }
            events.append(CurriculumEvent(
                date: date, kind: .practice, state: index >= 2 ? .repeated : .chosen, recall: nil, recordID: session.id
            ))
        }
        if let mastery = builder.mastery, mastery.isMastered,
           let date = mastery.masteredAt ?? mastery.lastObservedAt ?? mastery.presentedAt {
            events.append(CurriculumEvent(
                date: date, kind: .mastery, state: .mastered, recall: nil, recordID: mastery.id
            ))
        }
        for recall in builder.recalls {
            guard let date = recall.checkedAt else { continue }
            events.append(CurriculumEvent(
                date: date, kind: .recall, state: nil, recall: recall.outcome, recordID: recall.id
            ))
        }
        return events
    }

    // MARK: - Date Helpers

    private static func earliest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): min(l, r)
        case let (l?, nil): l
        case let (nil, r?): r
        default: nil
        }
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): max(l, r)
        case let (l?, nil): l
        case let (nil, r?): r
        default: nil
        }
    }
}
