import CoreData
import Foundation

/// What `StudentTrackDetailView` shows for one enrollment: the child, the
/// track's lessons and the child's marks on them. The timeline below it is
/// `StudentAreaProgressionViewModel`'s. Loading lives here, off the view, so a
/// test can pin what one open of the sheet materialises.
struct StudentTrackDetailLoad {
    /// Area and sequence parsed from the track title ("Area — Sequence"). Both
    /// stay empty when the title is not that shape, and nothing else is loaded.
    var area = ""
    var sequence = ""
    var student: CDStudent?
    var trackLessons: [CDLesson] = []
    var presentedLessonIDs: Set<String> = []
    var proficientLessonIDs: Set<String> = []
}

enum StudentTrackDetailLoader {
    static func load(
        enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, context: NSManagedObjectContext
    ) -> StudentTrackDetailLoad {
        // Parse area and sequence from track title (format: "Area — Group")
        let parts = track.title.components(separatedBy: " — ")
        guard parts.count == 2 else { return StudentTrackDetailLoad() }

        var load = StudentTrackDetailLoad()
        let area = parts[0].trimmingCharacters(in: .whitespaces)
        let sequence = parts[1].trimmingCharacters(in: .whitespaces)
        load.area = area
        load.sequence = sequence
        let studentID = enrollment.studentID
        load.student = student(withKey: studentID, in: context)

        // Lessons that could belong to this area/sequence: a store-side superset
        // of the trimmed, case-insensitive match applied here, in store order.
        load.trackLessons = SequenceTrackService.lessonCandidates(area: area, sequence: sequence, context: context)
            .filter { lesson in
                lesson.area.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(area) == .orderedSame &&
                lesson.sequence.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(sequence) == .orderedSame
            }
            .sorted { $0.orderInSequence < $1.orderInSequence }

        // The child's marks on those lessons (exact string matches, as before)
        let lessonIDStrings = load.trackLessons.compactMap { $0.id?.uuidString }
        let marks = CDFetchRequest(CDLessonPresentation.self)
        marks.predicate = NSPredicate(format: "studentID == %@ AND lessonID IN %@", studentID, lessonIDStrings)
        let studentPresentations = context.safeFetch(marks)

        load.presentedLessonIDs = Set(studentPresentations.map(\.lessonID))
        load.proficientLessonIDs = Set(studentPresentations.filter { $0.state == .proficient }.map(\.lessonID))
        return load
    }

    /// The first student whose `cloudKitKey` is `key`, found by id instead of
    /// a roster scan. `cloudKitKey` is the canonical upper-case id string (or
    /// "" for a row without one), so the exact string check is kept: a
    /// lower-case key finds nobody, and "" finds an id-less row, as before.
    private static func student(withKey key: String, in context: NSManagedObjectContext) -> CDStudent? {
        let candidate: CDStudent?
        if let id = UUID(uuidString: key) {
            candidate = context.object(CDStudent.self, id: id)
        } else {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id == nil")
            request.fetchLimit = 1
            candidate = context.safeFetch(request).first
        }
        return candidate?.cloudKitKey == key ? candidate : nil
    }
}
