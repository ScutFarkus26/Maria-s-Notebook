// LessonsPresentationHistoryProvider.swift
// Maria's Notebook
//
// Lightweight service to fetch presentation history for lessons.

import Foundation
import OSLog
import CoreData

enum LessonsPresentationHistoryProvider {
    private static let logger = Logger.lessons

    /// Combined fetch for both last presented date and count.
    /// More efficient than calling both methods separately.
    static func fetchPresentationHistory(
        lessonIDs: [UUID],
        context: NSManagedObjectContext
    ) -> (lastPresented: [UUID: Date], counts: [UUID: Int]) {
        guard !lessonIDs.isEmpty else { return ([:], [:]) }

        var lastPresented: [UUID: Date] = [:]
        var counts: [UUID: Int] = [:]
        let lessonIDStrings = Set(lessonIDs.map(\.uuidString))

        // Query all presented LessonAssignments, sorted by date desc
        let presentedState = LessonAssignmentState.presented.rawValue
        let descriptor = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", presentedState)
        descriptor.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]

        let assignments: [CDLessonAssignment]
        do {
            assignments = try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch lesson assignments: \(error)")
            return ([:], [:])
        }

        for assignment in assignments {
            guard lessonIDStrings.contains(assignment.lessonID),
                  let uuid = UUID(uuidString: assignment.lessonID) else { continue }

            // Count all presentations
            counts[uuid, default: 0] += 1

            // Store first (most recent) date
            if lastPresented[uuid] == nil, let presentedAt = assignment.presentedAt {
                lastPresented[uuid] = presentedAt
            }
        }

        return (lastPresented, counts)
    }
}
