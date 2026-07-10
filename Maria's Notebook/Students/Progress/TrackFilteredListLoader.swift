// TrackFilteredListLoader.swift
// Scoped fetches for TrackFilteredListSheet. Replaces the former whole-table
// fetches (every LessonAssignment, WorkModel, Note, and Lesson in the store)
// that re-ran on each body evaluation of the sheet.

import Foundation
import CoreData

/// Payload for `TrackFilteredListView`, fetched scoped to one enrollment + track.
/// Only the arrays the requested `TrackFilterType` reads are populated.
struct TrackFilteredListData {
    let lessonAssignments: [CDLessonAssignment]
    let workModels: [CDWorkModel]
    let notes: [CDNote]
    let lessons: [CDLesson]
}

enum TrackFilteredListLoader {

    @MainActor
    static func load(
        enrollment: CDStudentTrackEnrollmentEntity,
        track: CDTrackEntity,
        filterType: TrackFilterType,
        context: NSManagedObjectContext
    ) -> TrackFilteredListData {
        switch filterType {
        case .presentations:
            let assignments = fetchAssignments(track: track, enrollment: enrollment, context: context)
            return TrackFilteredListData(
                lessonAssignments: assignments,
                workModels: [],
                notes: [],
                lessons: fetchLessons(for: assignments, context: context)
            )
        case .work:
            return TrackFilteredListData(
                lessonAssignments: [],
                workModels: fetchWork(track: track, enrollment: enrollment, context: context),
                notes: [],
                lessons: []
            )
        case .notes:
            return TrackFilteredListData(
                lessonAssignments: [],
                workModels: [],
                notes: fetchNotes(enrollment: enrollment, context: context),
                lessons: []
            )
        }
    }

    // MARK: - Per-section fetches

    @MainActor
    private static func fetchAssignments(
        track: CDTrackEntity,
        enrollment: CDStudentTrackEnrollmentEntity,
        context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "trackID == %@ AND stateRaw == %@",
            track.id?.uuidString ?? "",
            LessonAssignmentState.presented.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
        // studentIDs is JSON-encoded Data, so membership is filtered in memory
        // over the already track-scoped result set.
        return context.safeFetch(request)
            .filter { $0.studentIDs.contains(enrollment.studentID) }
    }

    @MainActor
    private static func fetchLessons(
        for assignments: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) -> [CDLesson] {
        let lessonIDs = assignments.compactMap { UUID(uuidString: $0.lessonID) }
        guard !lessonIDs.isEmpty else { return [] }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", lessonIDs)
        return context.safeFetch(request)
    }

    @MainActor
    private static func fetchWork(
        track: CDTrackEntity,
        enrollment: CDStudentTrackEnrollmentEntity,
        context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "trackID == %@ AND studentID == %@",
            track.id?.uuidString ?? "",
            enrollment.studentID
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return context.safeFetch(request)
    }

    @MainActor
    private static func fetchNotes(
        enrollment: CDStudentTrackEnrollmentEntity,
        context: NSManagedObjectContext
    ) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "studentTrackEnrollmentID == %@",
            enrollment.id?.uuidString ?? ""
        )
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return context.safeFetch(request)
    }
}
