// BeforeLessonWork.swift
// What the Work half's "Before a Lesson" pill lists: open work that children
// in a lesson planned for the next three school days still have from earlier
// in that lesson's sequence, grouped under each lesson, soonest first.
//
// Built by the workspace on its debounced refresh, with the partition, never
// in a `body` pass: it is one `WorkToShowFirst` fetch for every lesson in the
// window.

import CoreData
import Foundation

struct BeforeLessonWork {
    /// One upcoming lesson and the earlier work its children have open.
    struct Section {
        /// The day and the lesson: two groups of one lesson on one day are
        /// one section, two lessons that share a name are two.
        let id: String
        /// "Today · Stamp Game Addition".
        let title: String
        let works: [CDWorkModel]
    }

    /// Soonest lesson first. A piece of work is listed once, under the
    /// soonest lesson it comes before.
    let sections: [Section]

    init(sections: [Section] = []) {
        self.sections = sections
    }

    /// The sections narrowed to `visibleIDs` (the search, kind and child
    /// filters), dropping any left empty.
    func sections(visibleTo visibleIDs: Set<UUID>) -> [Section] {
        sections.compactMap { section in
            let works = section.works.filter { $0.id.map(visibleIDs.contains) ?? false }
            return works.isEmpty ? nil : Section(id: section.id, title: section.title, works: works)
        }
    }

    /// Every work the pill lists, in its order.
    func works(visibleTo visibleIDs: Set<UUID>) -> [CDWorkModel] {
        sections(visibleTo: visibleIDs).flatMap(\.works)
    }

    // MARK: - Building

    /// - Parameters:
    ///   - presentations: the workspace's scheduled presentations; those not
    ///     in `days` are skipped.
    ///   - days: `LessonsAndWorkTriage.beforeLessonDays`.
    ///   - lessons: the whole library, for the sequences and the lesson names.
    static func build(
        presentations: [CDLessonAssignment],
        days: [Date],
        lessons: [CDLesson],
        in context: NSManagedObjectContext,
        now: Date = Date()
    ) -> BeforeLessonWork {
        let upcoming = presentations
            .filter { LessonsAndWorkTriage.isBeforeLesson(triageInput(for: $0), days: days) }
            .sorted(by: LessonAssignmentOrdering.isOrderedBefore)
        guard !upcoming.isEmpty else { return BeforeLessonWork() }

        var requests: [NSManagedObjectID: WorkToShowFirst.Request] = [:]
        for presentation in upcoming {
            requests[presentation.objectID] = WorkToShowFirst.Request(
                lessonID: presentation.resolvedLessonID.uuidString,
                studentIDs: Set(presentation.resolvedStudentIDs)
            )
        }
        let sequences = WorkToShowFirst.Sequences(lessons: lessons)
        let found = WorkToShowFirst.find(requests, sequences: sequences, in: context)

        var seen = Set<NSManagedObjectID>()
        var sections: [Section] = []
        var indexByID: [String: Int] = [:]
        for presentation in upcoming {
            // Earlier in the sequence first; ties in a fixed order, so the
            // grid doesn't reshuffle on each refresh.
            let items = (found[presentation.objectID] ?? [:]).values.joined().sorted { lhs, rhs in
                if lhs.step != rhs.step { return lhs.step < rhs.step }
                return (lhs.work.id?.uuidString ?? "") < (rhs.work.id?.uuidString ?? "")
            }
            let works = items.map(\.work).filter { seen.insert($0.objectID).inserted }
            guard !works.isEmpty else { continue }
            // Two groups of one lesson on one day read as one section.
            let id = sectionID(for: presentation)
            if let index = indexByID[id] {
                let merged = sections[index]
                sections[index] = Section(id: id, title: merged.title, works: merged.works + works)
            } else {
                indexByID[id] = sections.count
                sections.append(Section(
                    id: id, title: sectionTitle(for: presentation, order: sequences.order, now: now), works: works
                ))
            }
        }
        return BeforeLessonWork(sections: sections)
    }

    /// The day and the lesson, whatever either is called.
    private static func sectionID(for presentation: CDLessonAssignment) -> String {
        let day = presentation.scheduledFor.map { AppCalendar.startOfDay($0).timeIntervalSinceReferenceDate } ?? 0
        return "\(day)|\(presentation.resolvedLessonID.uuidString)"
    }

    private static func triageInput(for presentation: CDLessonAssignment) -> PresentationTriageInput {
        PresentationTriageInput(state: presentation.state, scheduledFor: presentation.scheduledFor)
    }

    /// "Today · Stamp Game Addition", "Thursday · Stamp Game Addition", and
    /// past a holiday week "Mon, Jan 5 · Stamp Game Addition".
    static func sectionTitle(for presentation: CDLessonAssignment, order: LessonSequenceOrder, now: Date) -> String {
        let name = LessonFormatter.lessonName(
            order.position(of: presentation.resolvedLessonID.uuidString)?.name,
            missing: LessonFormatter.untitledLesson
        )
        guard let day = presentation.scheduledFor else { return name }
        return "\(WorkToShowFirst.dayName(day, now: now)) · \(name)"
    }
}
