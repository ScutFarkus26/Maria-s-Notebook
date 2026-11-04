import CoreData
import Foundation

/// Where one child stands on one lesson sequence, read from the presentation
/// record: the sequence's lessons in order, which she has been given, which
/// she has mastered, and the lesson she is up to.
///
/// This is what a track enrollment and its steps used to store as rows
/// (`docs/Plans/Plan - Retire the track entities.md`). Nothing here is kept:
/// a standing is computed when a screen asks, from the child's own
/// `CDLessonPresentation` rows and the sequence's lessons.
struct SequenceStanding: Identifiable {
    let area: String
    let sequence: String
    /// The sequence's lessons in `orderInSequence`.
    let lessons: [CDLesson]
    /// Lessons the child has a presentation record for, by lesson id string.
    let givenLessonIDs: Set<String>
    /// Lessons with a mastery mark: `masteredAt` set or the mastered state
    /// (the rule the Curriculum Map and the Checklist share).
    let masteredLessonIDs: Set<String>
    /// The earliest date a lesson of the sequence was given to her.
    let firstGivenAt: Date?
    /// The most recent date a lesson of the sequence was given or marked.
    let lastActivityAt: Date?

    /// "Area|Sequence", trimmed: one standing per sequence.
    var id: String { Self.key(area: area, sequence: sequence) }
    /// The title the old track cards wore, "Area — Sequence".
    var title: String { "\(area) — \(sequence)" }

    var total: Int { lessons.count }
    var masteredCount: Int { lessons.filter { isMastered($0) }.count }
    var givenCount: Int { lessons.filter { isGiven($0) }.count }
    var progressPercent: Double { total > 0 ? Double(masteredCount) / Double(total) : 0 }

    /// Every lesson of the sequence carries a mastery mark.
    var isFinished: Bool { total > 0 && masteredCount == total }
    /// She has been given at least one lesson of it and has not mastered them all.
    var isInProgress: Bool { !givenLessonIDs.isEmpty && !isFinished }

    /// The lesson she is up to: the first in order she has not been given.
    /// `nil` once every lesson has been given, mastered or not.
    var nextLesson: CDLesson? { lessons.first { !isGiven($0) } }

    func isGiven(_ lesson: CDLesson) -> Bool {
        guard let id = lesson.id?.uuidString else { return false }
        return givenLessonIDs.contains(id)
    }

    func isMastered(_ lesson: CDLesson) -> Bool {
        guard let id = lesson.id?.uuidString else { return false }
        return masteredLessonIDs.contains(id)
    }

    static func key(area: String, sequence: String) -> String {
        "\(area.trimmed().folded())|\(sequence.trimmed().folded())"
    }

    /// Whether a presentation row counts as a mastery mark.
    static func isMasteryMark(_ row: CDLessonPresentation) -> Bool {
        row.masteredAt != nil || row.state == .proficient
    }
}

/// Builds standings for one child. Every read is scoped to her rows and to
/// the sequences they name; the classroom's rows stay in the store.
enum SequenceStandingLoader {

    /// Every sequence the child has a presentation record in, in curriculum
    /// order (area, then sequence as the lessons sort).
    static func standings(forStudentID studentID: String, in context: NSManagedObjectContext) -> [SequenceStanding] {
        let rows = presentationRows(forStudentID: studentID, in: context)
        guard !rows.isEmpty else { return [] }

        // The lessons her rows name, then the sequences those lessons belong to.
        let givenLessonIDs = Set(rows.map(\.lessonID))
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", givenLessonIDs.compactMap(UUID.init(uuidString:)))
        request.sortDescriptors = CDLesson.sortByCurriculumOrder
        let givenLessons = context.safeFetch(request)

        var seen = Set<String>()
        var result: [SequenceStanding] = []
        for lesson in givenLessons {
            let area = lesson.area.trimmed()
            let sequence = lesson.sequence.trimmed()
            guard !area.isEmpty, !sequence.isEmpty else { continue }
            guard seen.insert(SequenceStanding.key(area: area, sequence: sequence)).inserted else { continue }
            result.append(standing(area: area, sequence: sequence, rows: rows, in: context))
        }
        return result
    }

    /// The child's standing on one sequence, whether or not she has started it.
    static func standing(
        forStudentID studentID: String, area: String, sequence: String, in context: NSManagedObjectContext
    ) -> SequenceStanding {
        standing(
            area: area.trimmed(), sequence: sequence.trimmed(),
            rows: presentationRows(forStudentID: studentID, in: context), in: context
        )
    }

    /// The sequence's lessons in order: a store-side superset of the trimmed,
    /// case-insensitive match applied here (`SequenceTrackService.couldEqualPredicate`).
    static func sequenceLessons(area: String, sequence: String, in context: NSManagedObjectContext) -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = SequenceTrackService.couldEqualPredicate(area: area, sequence: sequence)
        request.sortDescriptors = CDLesson.sortByCurriculumOrder
        return context.safeFetch(request)
            .filter {
                $0.area.trimmed().caseInsensitiveCompare(area) == .orderedSame &&
                $0.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame
            }
            .sorted { $0.orderInSequence < $1.orderInSequence }
    }

    // MARK: - Pieces

    private static func presentationRows(
        forStudentID studentID: String, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "studentID == %@", studentID)
        return context.safeFetch(request)
    }

    private static func standing(
        area: String, sequence: String, rows: [CDLessonPresentation], in context: NSManagedObjectContext
    ) -> SequenceStanding {
        let lessons = sequenceLessons(area: area, sequence: sequence, in: context)
        let lessonIDs = Set(lessons.compactMap { $0.id?.uuidString })
        // Her rows match the way the rest of the app links them, by exact id
        // string, with the upper-case form the store writes.
        let sequenceRows = rows.filter { lessonIDs.contains($0.lessonID.uppercased()) }
        let dates = sequenceRows.flatMap { [$0.presentedAt, $0.masteredAt, $0.lastObservedAt].compactMap { $0 } }
        return SequenceStanding(
            area: area,
            sequence: sequence,
            lessons: lessons,
            givenLessonIDs: Set(sequenceRows.map { $0.lessonID.uppercased() }),
            masteredLessonIDs: Set(
                sequenceRows.filter(SequenceStanding.isMasteryMark).map { $0.lessonID.uppercased() }
            ),
            firstGivenAt: sequenceRows.compactMap(\.presentedAt).min(),
            lastActivityAt: dates.max()
        )
    }
}
