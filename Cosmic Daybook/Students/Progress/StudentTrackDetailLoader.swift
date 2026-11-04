import CoreData
import Foundation

/// What `StudentTrackDetailView` shows for one child on one sequence: the
/// sequence's lessons and the child's marks on them, as a fresh
/// `SequenceStanding`. The timeline below it is
/// `StudentAreaProgressionViewModel`'s. Loading lives here, off the view, so a
/// test can pin what one open of the sheet materialises.
struct StudentTrackDetailLoad {
    var standing: SequenceStanding
    var trackLessons: [CDLesson] { standing.lessons }
    var presentedLessonIDs: Set<String> { standing.givenLessonIDs }
    var proficientLessonIDs: Set<String> { standing.masteredLessonIDs }
}

enum StudentTrackDetailLoader {
    /// Re-reads the standing from the store, so a sheet opened from a card
    /// that was loaded a while ago shows what is on file now.
    static func load(
        student: CDStudent, area: String, sequence: String, context: NSManagedObjectContext
    ) -> StudentTrackDetailLoad {
        let standing = SequenceStandingLoader.standing(
            forStudentID: student.id?.uuidString ?? "", area: area, sequence: sequence, in: context
        )
        return StudentTrackDetailLoad(standing: standing)
    }
}
