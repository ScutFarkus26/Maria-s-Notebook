import Foundation
import SwiftData

// NEW: Updated "Scan and Backfill" logic that groups students together
@MainActor
func scanAndBackfillBlockedLessonsGrouped(modelContext: ModelContext) throws -> String {
    // 1. Fetch all Incomplete Contracts (Active or Review)
    let incompleteContracts = try modelContext.fetch(FetchDescriptor<WorkContract>(predicate: #Predicate {
        $0.statusRaw == "active" || $0.statusRaw == "review"
    }))
    
    if incompleteContracts.isEmpty { return "No active work found." }

    // 2. Fetch Metadata (Lessons and existing Plans)
    let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
    let lessonsByID = allLessons.toDictionary(by: \.id)
    
    // Group lessons by Subject|Group and sort by order
    let lessonsByGroup: [String: [Lesson]] = allLessons.grouped { l in
        "\(l.subject.trimmed())|\(l.group.trimmed())".lowercased()
    }
    let sortedLessonsByGroup = lessonsByGroup.mapValues { $0.sorted { $0.orderInGroup < $1.orderInGroup } }

    // Track what is already planned to avoid duplicates
    // Set of "StudentUUID|LessonUUID"
    let allSLs = try modelContext.fetch(FetchDescriptor<StudentLesson>())
    var existingPlans = Set<String>()
    for sl in allSLs {
        for sid in sl.studentIDs {
            existingPlans.insert("\(sid)|\(sl.lessonID)")
        }
    }
    
    // Cache students for object linking
    let allStudents = try modelContext.fetch(FetchDescriptor<Student>())
    let studentsByID = allStudents.toDictionary(by: { $0.id.uuidString })

    // 3. Accumulate students who need the NEXT lesson
    // Map: [NextLessonID : Set<StudentIDString>]
    var pendingNextLessons: [UUID : Set<String>] = [:]
    
    for contract in incompleteContracts {
        // Find the lesson associated with this work
        guard let currentLessonID = UUID(uuidString: contract.lessonID),
              let currentLesson = lessonsByID[currentLessonID] else { continue }
        
        // Find the sequence for this lesson
        let groupKey = "\(currentLesson.subject.trimmed())|\(currentLesson.group.trimmed())".lowercased()
        guard let sequence = sortedLessonsByGroup[groupKey] else { continue }
        
        // Find the index and check if there is a next lesson
        guard let idx = sequence.firstIndex(where: { $0.id == currentLessonID }),
              idx + 1 < sequence.count else { continue }
        
        let nextLesson = sequence[idx + 1]
        let studentIDStr = contract.studentID
        
        // Check if this next lesson is already planned for this specific student
        let planKey = "\(studentIDStr)|\(nextLesson.id)"
        if !existingPlans.contains(planKey) {
            // Queue this student for this lesson
            if pendingNextLessons[nextLesson.id] == nil {
                pendingNextLessons[nextLesson.id] = []
            }
            pendingNextLessons[nextLesson.id]?.insert(studentIDStr)
        }
    }
    
    // 4. Create Grouped StudentLessons
    var addedGroups = 0
    var addedStudents = 0
    
    for (lessonID, studentIDStrings) in pendingNextLessons {
        guard let lesson = lessonsByID[lessonID] else { continue }
        
        let validStudents = studentIDStrings.compactMap { studentsByID[$0] }
        if validStudents.isEmpty { continue }
        
        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lessonID,
            studentIDs: validStudents.map { $0.id },
            createdAt: Date(),
            scheduledFor: nil, // Inbox
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        // Set relationships
        newSL.lesson = lesson
        newSL.students = validStudents
        
        modelContext.insert(newSL)
        addedGroups += 1
        addedStudents += validStudents.count
    }
    
    try modelContext.save()
    
    if addedGroups == 0 {
        return "All caught up! No new lessons needed."
    } else {
        return "Added \(addedGroups) On Deck items for \(addedStudents) students."
    }
}

// NEW: Consolidate Existing Splits
@MainActor
func consolidateOnDeckLessons(modelContext: ModelContext) throws -> String {
    // 1. Fetch all On Deck items
    let descriptor = FetchDescriptor<StudentLesson>(
        predicate: #Predicate { $0.scheduledFor == nil && $0.givenAt == nil }
    )
    let allInbox = try modelContext.fetch(descriptor)
    
    // 2. Group by Lesson
    let grouped = Dictionary(grouping: allInbox) { $0.lessonID }
    
    var consolidatedCount = 0
    var deletedCount = 0
    
    for (_, items) in grouped {
        if items.count > 1 {
            // We found duplicates!
            // 1. Keep the oldest one (or just the first one)
            let sorted = items.sorted { $0.createdAt < $1.createdAt }
            guard let target = sorted.first else { continue }
            let others = sorted.dropFirst()
            
            // 2. Merge Students
            var allStudents = Set(target.students)
            for other in others {
                for s in other.students {
                    allStudents.insert(s)
                }
                // 3. Delete the duplicate
                modelContext.delete(other)
                deletedCount += 1
            }
            
            target.students = Array(allStudents)
            target.studentIDs = target.students.map { $0.id.uuidString } // Sync IDs - convert to strings for CloudKit
            consolidatedCount += 1
        }
    }
    
    try modelContext.save()
    return "Consolidated \(consolidatedCount) groups. Removed \(deletedCount) duplicate items."
}
