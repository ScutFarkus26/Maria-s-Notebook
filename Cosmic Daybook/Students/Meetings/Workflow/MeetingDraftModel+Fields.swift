import CoreData
import Foundation

// The draft model's pure helpers: reading stored fields, merging two
// windows' work decisions, and the lessons Ready for Next can plan.
extension MeetingDraftModel {

    /// What a model changed since it last wrote: whole fields, and item by
    /// item for the keyed ones, so a flush writes only those and takes the
    /// rest from the stored draft. A work's note and its decision are tracked
    /// apart: a note typed here mustn't carry a stale "no decision" over
    /// another window's Re-present (bug hunt 2026-10-10 review).
    struct Changes {
        var fields: Set<Field> = []
        /// Focus items ticked off or dropped, or untouched again.
        var focusIDs: Set<UUID> = []
        /// Work whose note changed.
        var noteWorkIDs: Set<UUID> = []
        /// Work whose decision (reviewed, Re-present, Ready for Next) or receipt changed.
        var decisionWorkIDs: Set<UUID> = []
    }

    /// The draft's single-value fields, for `Changes`.
    enum Field: Hashable {
        case reflection, guideNotes, requests, requestLessonIDs, nextMeetingDate, pendingFocus
    }

    /// Whether Ready for Next has a lesson to put On Deck after `lessonID`.
    func hasNextLesson(after lessonID: String) -> Bool {
        UUID(uuidString: lessonID).map(lessonsWithNext.contains) ?? false
    }

    static func ids(_ strings: [String]?) -> Set<UUID> {
        Set((strings ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func keyed<Value>(_ stored: [String: Value]?) -> [UUID: Value] {
        Dictionary(
            (stored ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Mine for the work in `kept`, theirs for the rest.
    static func merged(_ mine: Set<UUID>, _ theirs: Set<UUID>, keeping kept: Set<UUID>) -> Set<UUID> {
        mine.intersection(kept).union(theirs.subtracting(kept))
    }

    /// Mine for the work in `kept`, theirs for the rest.
    static func merged<Value>(
        _ mine: [UUID: Value], _ theirs: [UUID: Value], keeping kept: Set<UUID>
    ) -> [UUID: Value] {
        var result = theirs.filter { !kept.contains($0.key) }
        for (key, value) in mine where kept.contains(key) {
            result[key] = value
        }
        return result
    }

    /// The work whose entry differs between two versions of a keyed field.
    static func changedKeys<Value: Equatable>(_ old: [UUID: Value], _ new: [UUID: Value]) -> Set<UUID> {
        Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
    }

    /// Ready for Next plans what `PlanNextLessonService.findNextLesson` finds:
    /// the lesson after this one in its area and sequence. One lesson fetch.
    /// Lessons tied for last place count as having none, so the button never
    /// offers a plan Complete can't make.
    static func lessonsWithNext(in context: NSManagedObjectContext) -> Set<UUID> {
        var sequences: [String: [CDLesson]] = [:]
        for lesson in context.safeFetch(CDFetchRequest(CDLesson.self)) {
            let area = lesson.area.trimmed().lowercased()
            let sequence = lesson.sequence.trimmed().lowercased()
            guard !area.isEmpty, !sequence.isEmpty else { continue }
            sequences[area + "\u{1F}" + sequence, default: []].append(lesson)
        }
        var result: Set<UUID> = []
        for lessons in sequences.values {
            guard let last = lessons.map(\.orderInSequence).max() else { continue }
            for lesson in lessons where lesson.orderInSequence < last {
                if let id = lesson.id { result.insert(id) }
            }
        }
        return result
    }
}
