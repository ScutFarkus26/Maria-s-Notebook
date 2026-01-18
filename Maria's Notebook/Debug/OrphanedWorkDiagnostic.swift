import Foundation
import SwiftData

/// Diagnostic utility to find work items with missing lesson references
/// and identify what lesson IDs are being referenced but don't exist.
enum OrphanedWorkDiagnostic {

    struct DiagnosticResult {
        let totalWorkItems: Int
        let orphanedWorkItems: Int
        let missingLessonIDs: [String: Int]  // lessonID -> count of work items referencing it
        let existingLessons: Int
        let workItemsWithValidLessons: Int
    }

    /// Run diagnostic and return results
    static func run(context: ModelContext) -> DiagnosticResult {
        do {
            // Fetch all lessons and create a lookup set
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let lessonIDs = Set(lessons.map { $0.id })

            // Fetch all work items
            let workModels = try context.fetch(FetchDescriptor<WorkModel>())

            var missingLessonIDs: [String: Int] = [:]
            var validCount = 0

            for work in workModels {
                let lessonID = work.lessonID

                // Skip empty lesson IDs
                if lessonID.isEmpty { continue }

                // Check if the lesson ID resolves to an existing lesson
                if let uuid = UUID(uuidString: lessonID), lessonIDs.contains(uuid) {
                    validCount += 1
                } else {
                    // Track this missing lesson ID
                    missingLessonIDs[lessonID, default: 0] += 1
                }
            }

            return DiagnosticResult(
                totalWorkItems: workModels.count,
                orphanedWorkItems: missingLessonIDs.values.reduce(0, +),
                missingLessonIDs: missingLessonIDs,
                existingLessons: lessons.count,
                workItemsWithValidLessons: validCount
            )
        } catch {
            print("ORPHANED WORK DIAGNOSTIC ERROR:", error)
            return DiagnosticResult(
                totalWorkItems: 0,
                orphanedWorkItems: 0,
                missingLessonIDs: [:],
                existingLessons: 0,
                workItemsWithValidLessons: 0
            )
        }
    }

    /// Print detailed diagnostic report to console
    static func printReport(context: ModelContext) {
        let result = run(context: context)

        print("=" * 60)
        print("ORPHANED WORK DIAGNOSTIC REPORT")
        print("=" * 60)
        print("Total Work Items: \(result.totalWorkItems)")
        print("Work Items with Valid Lessons: \(result.workItemsWithValidLessons)")
        print("Orphaned Work Items: \(result.orphanedWorkItems)")
        print("Existing Lessons in Database: \(result.existingLessons)")
        print("-" * 60)

        if result.missingLessonIDs.isEmpty {
            print("No orphaned work items found!")
        } else {
            print("Missing Lesson IDs (referenced by work but don't exist):")
            for (lessonID, count) in result.missingLessonIDs.sorted(by: { $0.value > $1.value }) {
                let shortID = String(lessonID.prefix(6)).uppercased()
                print("  - Lesson \(shortID)... (\(lessonID)): \(count) work item(s)")
            }
        }
        print("=" * 60)
    }

    /// Search for lessons by name pattern (case-insensitive)
    static func searchLessons(matching pattern: String, context: ModelContext) -> [Lesson] {
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let lowercasePattern = pattern.lowercased()
            return lessons.filter { lesson in
                lesson.name.lowercased().contains(lowercasePattern) ||
                lesson.subject.lowercased().contains(lowercasePattern) ||
                lesson.group.lowercased().contains(lowercasePattern)
            }
        } catch {
            print("LESSON SEARCH ERROR:", error)
            return []
        }
    }

    /// Print all lessons matching a search pattern
    static func printLessonSearch(matching pattern: String, context: ModelContext) {
        let results = searchLessons(matching: pattern, context: context)

        print("=" * 60)
        print("LESSON SEARCH: '\(pattern)'")
        print("=" * 60)

        if results.isEmpty {
            print("No lessons found matching '\(pattern)'")
        } else {
            print("Found \(results.count) lesson(s):")
            for lesson in results.sorted(by: { $0.name < $1.name }) {
                print("  - \(lesson.name)")
                print("    Subject: \(lesson.subject.isEmpty ? "(none)" : lesson.subject)")
                print("    Group: \(lesson.group.isEmpty ? "(none)" : lesson.group)")
                print("    ID: \(lesson.id)")
            }
        }
        print("=" * 60)
    }

    /// List all unique subjects in the database
    static func listSubjects(context: ModelContext) -> [String: Int] {
        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            var subjects: [String: Int] = [:]
            for lesson in lessons {
                let subject = lesson.subject.isEmpty ? "(No Subject)" : lesson.subject
                subjects[subject, default: 0] += 1
            }
            return subjects
        } catch {
            print("LIST SUBJECTS ERROR:", error)
            return [:]
        }
    }

    /// Print all subjects with lesson counts
    static func printSubjects(context: ModelContext) {
        let subjects = listSubjects(context: context)

        print("=" * 60)
        print("LESSONS BY SUBJECT")
        print("=" * 60)

        for (subject, count) in subjects.sorted(by: { $0.key < $1.key }) {
            print("  \(subject): \(count) lesson(s)")
        }
        print("=" * 60)
    }
}

// Helper for string repetition
private func *(lhs: String, rhs: Int) -> String {
    return String(repeating: lhs, count: rhs)
}
