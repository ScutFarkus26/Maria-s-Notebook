// TrackFilteredListLoader.swift
// Scoped fetches for TrackFilteredListSheet: one child, one sequence's lessons.

import Foundation
import CoreData

/// Payload for `TrackFilteredListView`, fetched scoped to one child and one
/// sequence. Only the arrays the requested `TrackFilterType` reads are populated.
struct TrackFilteredListData {
    let lessonAssignments: [CDLessonAssignment]
    let workModels: [CDWorkModel]
    let notes: [CDNote]
    let lessons: [CDLesson]
}

enum TrackFilteredListLoader {

    /// The same rules as the card's counts (`SequenceActivityFetches`), so
    /// the sheet lists what the badge counted.
    static func load(
        studentID: String,
        standing: SequenceStanding,
        filterType: TrackFilterType,
        context: NSManagedObjectContext
    ) -> TrackFilteredListData {
        let lessonIDs = standing.lessons.compactMap { $0.id?.uuidString }
        switch filterType {
        case .presentations:
            return TrackFilteredListData(
                lessonAssignments: SequenceActivityFetches.presentedAssignments(
                    studentID: studentID, lessonIDs: lessonIDs, in: context
                ),
                workModels: [],
                notes: [],
                lessons: standing.lessons
            )
        case .work:
            return TrackFilteredListData(
                lessonAssignments: [],
                workModels: SequenceActivityFetches.work(studentID: studentID, lessonIDs: lessonIDs, in: context),
                notes: [],
                lessons: []
            )
        case .notes:
            return TrackFilteredListData(
                lessonAssignments: [],
                workModels: [],
                notes: SequenceActivityFetches.notes(studentID: studentID, lessonIDs: lessonIDs, in: context),
                lessons: []
            )
        }
    }
}
