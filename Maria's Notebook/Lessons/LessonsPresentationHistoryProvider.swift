// LessonsPresentationHistoryProvider.swift
// Maria's Notebook
//
// Lightweight service to fetch presentation history for lessons.

import Foundation
import OSLog
import CoreData

@MainActor
enum LessonsPresentationHistoryProvider {
    private static let logger = Logger.lessons

    /// Fetches the most recent presentedAt date for each lesson ID.
    /// Returns a dictionary mapping lesson UUIDs to their most recent presentation date.
    static func fetchLastPresentedDates(
        lessonIDs: [UUID],
        context: NSManagedObjectContext
    ) -> [UUID: Date] {
        guard !lessonIDs.isEmpty else { return [:] }

        var result: [UUID: Date] = [:]
        let lessonIDStrings = Set(lessonIDs.map(\.uuidString))

        // Query all presented LessonAssignments
        let presentedState = LessonAssignmentState.presented.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", presentedState as CVarArg)
        descriptor.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]

        let assignments: [CDLessonAssignment]
        do {
            assignments = try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch lesson assignments: \(error)")
            return [:]
        }

        // Filter to our lesson IDs and take most recent per lesson
        for assignment in assignments {
            guard lessonIDStrings.contains(assignment.lessonID),
                  let uuid = UUID(uuidString: assignment.lessonID),
                  let presentedAt = assignment.presentedAt else { continue }

            // Only store the first (most recent) date for each lesson
            if result[uuid] == nil {
                result[uuid] = presentedAt
            }
        }

        return result
    }

    /// Fetches the total presentation count for each lesson ID.
    /// Returns a dictionary mapping lesson UUIDs to their presentation count.
    static func fetchPresentationCounts(
        lessonIDs: [UUID],
        context: NSManagedObjectContext
    ) -> [UUID: Int] {
        guard !lessonIDs.isEmpty else { return [:] }

        var result: [UUID: Int] = [:]
        let lessonIDStrings = Set(lessonIDs.map(\.uuidString))

        // Query all presented LessonAssignments
        let presentedState = LessonAssignmentState.presented.rawValue
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "stateRaw == %@", presentedState)

        let assignments: [CDLessonAssignment]
        do {
            assignments = try context.fetch(descriptor)
        } catch {
            logger.warning("Failed to fetch lesson assignments: \(error)")
            return [:]
        }

        // Count presentations per lesson
        for assignment in assignments {
            guard lessonIDStrings.contains(assignment.lessonID),
                  let uuid = UUID(uuidString: assignment.lessonID) else { continue }

            result[uuid, default: 0] += 1
        }

        return result
    }

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
