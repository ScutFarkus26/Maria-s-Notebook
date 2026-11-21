//
//  ReadyForNextEngine+Prerequisites.swift
//  Cosmic Daybook
//
//  A lesson's prerequisites from other sequences, as a reason to look first.
//
//  `prerequisiteLessonIDs` was stored, shown on the lesson page and backed up,
//  but nothing read it for readiness (domain-logic review A6). A prerequisite
//  she hasn't been given now holds her at "Ready, check first" with a plain
//  reason, "Equivalent Figures not yet presented", which the screens show
//  after "Check first: ". It is a reason to look, never a lock: the lesson
//  before her in its own sequence still decides Ready and Not ready yet, and
//  the guide can give the lesson anyway. The Checklist and the ready queue
//  (Groups, Today, the ladder, `students_ready`) both read this one rule.
//
//  The record is read here, over the prerequisites alone, rather than from
//  the caller's index, which may be scoped to other lessons: a prerequisite
//  the index never read would read as not given.
//

import CoreData
import Foundation

nonisolated extension ReadinessVerdict {

    /// This verdict with `reasons` added as things to check first: Ready
    /// becomes Ready, check first; Not ready yet stays as it is.
    func checkingFirst(_ reasons: [String]) -> ReadinessVerdict {
        guard !reasons.isEmpty, tier != .notReady else { return self }
        return ReadinessVerdict(tier: .almostReady, reasons: self.reasons + reasons)
    }
}

extension ReadyForNextEngine {

    /// "Equivalent Figures not yet presented".
    nonisolated static func prerequisiteReason(_ name: String) -> String {
        "\(name) not yet presented"
    }

    /// The prerequisites of some lessons and what the record says about them
    /// for some children, read once.
    @MainActor
    struct PrerequisiteRecord {
        /// lesson ID string → its prerequisites' ID strings, in the order the
        /// lesson lists them. Only lessons that have any.
        private let prerequisites: [String: [String]]
        /// Prerequisite ID string → its name, for the ones still in the library.
        private let names: [String: String]
        private let index: PresentationRecordIndex?

        /// - Parameters:
        ///   - lessons: the lessons whose prerequisites count.
        ///   - students: the children asked about, as UUID strings.
        init(lessons: [CDLesson], students: Set<String>, in context: NSManagedObjectContext) {
            var prerequisites: [String: [String]] = [:]
            for lesson in lessons {
                guard let id = lesson.id else { continue }
                let listed = lesson.prerequisiteLessonUUIDs.filter { $0 != id }.map(\.uuidString)
                if !listed.isEmpty { prerequisites[id.uuidString] = listed }
            }
            let wanted = Set(prerequisites.values.joined())
            guard !wanted.isEmpty, !students.isEmpty else {
                self.prerequisites = [:]
                names = [:]
                index = nil
                return
            }
            let request = CDFetchRequest(CDLesson.self)
            request.predicate = NSPredicate(format: "id IN %@", wanted.compactMap(UUID.init(uuidString:)))
            var names: [String: String] = [:]
            for lesson in context.safeFetch(request) where !lesson.isDeleted {
                guard let id = lesson.id?.uuidString else { continue }
                names[id] = lesson.name.trimmed().isEmpty ? "Untitled Lesson" : lesson.name.trimmed()
            }
            self.prerequisites = prerequisites
            self.names = names
            index = PresentationRecordIndex(lessonIDs: Set(names.keys), students: students, in: context)
        }

        /// One reason per prerequisite of `lessonID` she hasn't been given,
        /// in the lesson's order. A prerequisite no longer in the library
        /// says nothing.
        func reasons(lesson lessonID: String, student studentID: String) -> [String] {
            guard let index, let listed = prerequisites[lessonID] else { return [] }
            return listed.compactMap { prerequisiteID in
                guard let name = names[prerequisiteID],
                      index.given(student: studentID, lesson: prerequisiteID) == nil else { return nil }
                return ReadyForNextEngine.prerequisiteReason(name)
            }
        }
    }
}
