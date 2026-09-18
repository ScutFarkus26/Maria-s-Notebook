import CoreData
import Foundation

/// Store-side scoping for `SequenceTrackService`'s reads. Every helper is a
/// superset of the exact in-memory comparison the service still applies, so
/// the rows it acts on are unchanged; the rest of the table stays in the store.
extension SequenceTrackService {

    // MARK: - Scoped reads

    /// A store-side superset of "trimmed value equals `value` ignoring
    /// case": any stored string whose trimmed form matches contains `value`.
    /// Callers keep applying the exact in-memory comparison, so the result
    /// is unchanged; only the rows that could never match stay in the store.
    /// An empty value reads everything, as `CONTAINS ""` does not.
    static func couldEqualPredicate(area: String, sequence: String) -> NSPredicate? {
        guard !area.isEmpty, !sequence.isEmpty else { return nil }
        return NSPredicate(format: "area CONTAINS[cd] %@ AND sequence CONTAINS[cd] %@", area, sequence)
    }

    /// Sequence tracks that could be the one for `area` / `sequence`.
    static func sequenceTrackCandidates(
        area: String, sequence: String, context: NSManagedObjectContext
    ) -> [CDSequenceTrackEntity] {
        let request = CDFetchRequest(CDSequenceTrackEntity.self)
        request.predicate = couldEqualPredicate(area: area, sequence: sequence)
        return context.safeFetch(request)
    }

    /// Lessons that could belong to `area` / `sequence` (see `couldEqualPredicate`).
    static func lessonCandidates(
        area: String, sequence: String, context: NSManagedObjectContext
    ) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = couldEqualPredicate(area: area, sequence: sequence)
        return context.safeFetch(request)
    }

    /// The lessons of `area` / `sequence`, in sequence order.
    static func sequenceLessons(
        area: String, sequence: String, context: NSManagedObjectContext
    ) -> [CDLesson] {
        lessonCandidates(area: area, sequence: sequence, context: context).filter { lesson in
            lesson.area.trimmed().caseInsensitiveCompare(area) == .orderedSame &&
            lesson.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame
        }
    }

    /// Tracks whose trimmed title could equal `trackTitle` (case-sensitive).
    static func trackCandidates(title trackTitle: String, context: NSManagedObjectContext) -> [CDTrackEntity] {
        let request = CDFetchRequest(CDTrackEntity.self)
        request.predicate = NSPredicate(format: "title CONTAINS %@", trackTitle)
        return context.safeFetch(request)
    }
}
