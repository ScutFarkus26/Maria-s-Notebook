import Foundation
import SwiftData

/// A maintenance utility to merge duplicate Student records by normalized full name.
/// - Strategy:
///   - Group students by normalized name (first + last, lowercased, trimmed, single-spaced).
///   - For any group with more than one student:
///       - Choose a primary student to keep (prefers: earliest dateStarted, then earliest birthday, then lowest manualOrder).
///       - Merge fields into the primary (fill missing birthday/dateStarted/level if primary lacks them).
///       - Update references in StudentLesson.studentIDs and WorkModel.participants to point to the primary.
///       - Delete redundant students.
/// - Returns a summary of merges performed.
struct StudentDuplicatesCleaner {
    struct DuplicateGroup {
        let nameKey: String
        let members: [Student]
    }

    struct MergePlan {
        let primaryID: UUID
        let duplicateIDs: [UUID]
    }

    struct Summary {
        let groupsConsidered: Int
        let groupsMerged: Int
        let studentsDeleted: Int
        let referencesUpdated: Int
    }

    static func findDuplicateGroups(using context: ModelContext) throws -> [DuplicateGroup] {
        let students = try context.fetch(FetchDescriptor<Student>())
        var groups: [String: [Student]] = [:]
        for s in students {
            let key = "\(s.firstName) \(s.lastName)".normalizedNameKey()
            groups[key, default: []].append(s)
        }
        return groups
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(nameKey: $0.key, members: $0.value) }
    }

    static func defaultPrimary(for members: [Student]) -> Student? {
        return choosePrimary(from: members)
    }

    static func merge(plans: [MergePlan], using context: ModelContext) throws -> Summary {
        if plans.isEmpty { return Summary(groupsConsidered: 0, groupsMerged: 0, studentsDeleted: 0, referencesUpdated: 0) }

        // Pre-fetch related models for reference updates
        let studentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
        let works = try context.fetch(FetchDescriptor<WorkModel>())

        let groupsConsidered = plans.count
        var groupsMerged = 0
        var studentsDeleted = 0
        var referencesUpdated = 0

        // Build lookup for Students by ID
        let allStudents = try context.fetch(FetchDescriptor<Student>())
        let byID: [UUID: Student] = Dictionary(uniqueKeysWithValues: allStudents.map { ($0.id, $0) })

        for plan in plans {
            guard let primary = byID[plan.primaryID] else { continue }
            let duplicates: [Student] = plan.duplicateIDs.compactMap { byID[$0] }
            if duplicates.isEmpty { continue }

            // Merge fields into primary
            for dup in duplicates {
                if primary.dateStarted == nil, let ds = dup.dateStarted { primary.dateStarted = ds }
                if dup.birthday < primary.birthday { primary.birthday = dup.birthday }
                if primary.level != dup.level {
                    if primary.level == .lower && dup.level == .upper { primary.level = .upper }
                }
            }

            // Update references in StudentLesson
            for i in 0..<studentLessons.count {
                let sl = studentLessons[i]
                if sl.studentIDs.contains(where: { plan.duplicateIDs.contains($0) }) {
                    var set = Set(sl.studentIDs)
                    for d in plan.duplicateIDs { set.remove(d) }
                    set.insert(primary.id)
                    let newList = Array(set)
                    if newList != sl.studentIDs {
                        sl.studentIDs = newList
                        referencesUpdated += 1
                    }
                }
            }

            // Update references in WorkModel participants
            for i in 0..<works.count {
                let w = works[i]
                var changed = false

                // 1) Repoint any participant entries that reference a duplicate student ID
                for p in w.participants {
                    if plan.duplicateIDs.contains(p.studentID) {
                        p.studentID = primary.id
                        changed = true
                    }
                }

                // 2) Deduplicate participants so there is at most one per student
                var seen: [UUID: WorkParticipantEntity] = [:]
                for p in w.participants {
                    if let existing = seen[p.studentID] {
                        // Merge completion: prefer a non-nil date; if both non-nil, keep earliest
                        switch (existing.completedAt, p.completedAt) {
                        case (nil, let r?):
                            existing.completedAt = r
                            changed = true
                        case (let l?, let r?):
                            if r < l {
                                existing.completedAt = r
                                changed = true
                            }
                        default:
                            break
                        }
                        // Remove the duplicate participant
                        context.delete(p)
                        changed = true
                    } else {
                        seen[p.studentID] = p
                    }
                }

                if changed {
                    referencesUpdated += 1
                }
            }

            // Delete duplicates
            for d in duplicates {
                context.delete(d)
                studentsDeleted += 1
            }

            groupsMerged += 1
        }

        try context.save()
        return Summary(groupsConsidered: groupsConsidered, groupsMerged: groupsMerged, studentsDeleted: studentsDeleted, referencesUpdated: referencesUpdated)
    }

    static func mergeDuplicates(using context: ModelContext) throws -> Summary {
        let groups = try findDuplicateGroups(using: context)
        if groups.isEmpty { return Summary(groupsConsidered: 0, groupsMerged: 0, studentsDeleted: 0, referencesUpdated: 0) }
        var plans: [MergePlan] = []
        for g in groups {
            guard let primary = defaultPrimary(for: g.members) else { continue }
            let dupIDs = g.members.map { $0.id }.filter { $0 != primary.id }
            if !dupIDs.isEmpty {
                plans.append(MergePlan(primaryID: primary.id, duplicateIDs: dupIDs))
            }
        }
        return try merge(plans: plans, using: context)
    }

    private static func choosePrimary(from members: [Student]) -> Student? {
        return members.sorted { lhs, rhs in
            // Prefer earliest dateStarted (nil is worst)
            switch (lhs.dateStarted, rhs.dateStarted) {
            case let (l?, r?):
                if l != r { return l < r }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                break
            }
            // Prefer earliest birthday
            if lhs.birthday != rhs.birthday { return lhs.birthday < rhs.birthday }
            // Prefer lower manualOrder
            if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder < rhs.manualOrder }
            // Stable fallback by id
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }
}
