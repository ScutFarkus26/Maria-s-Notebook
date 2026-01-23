import Foundation
import SwiftData

// MARK: - Relationship Backfill Service

/// Service responsible for backfilling relationships between entities.
/// Handles linking StudentLessons to Presentations, Notes, and other related entities.
enum RelationshipBackfillService {

    // MARK: - StudentLesson Relationships

    /// Backfill StudentLesson relationships from legacy studentIDs and lessonID strings.
    /// One-time migration that ensures relationship arrays are populated from denormalized ID fields.
    /// Idempotent: guarded by a UserDefaults flag.
    /// Yields periodically to allow UI updates during large migrations.
    static func backfillRelationshipsIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.relationships.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            // OPTIMIZATION: Fetch all data once (these are relatively small lookups)
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let students = context.safeFetch(FetchDescriptor<Student>())
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            let studentsByID = students.toDictionary(by: \.id)
            let lessonsByID = lessons.toDictionary(by: \.id)

            // OPTIMIZATION: Process in batches and save periodically to avoid memory pressure
            let batchSize = 1000
            var changed = false
            var processed = 0

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                // Yield periodically to prevent blocking UI
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    // CloudKit compatibility: Convert String lessonID to UUID for lookup
                    guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { continue }
                    let targetLesson = lessonsByID[lessonIDUUID]
                    let targetStudents: [Student] = sl.studentIDs.compactMap { idString in
                        guard let id = UUID(uuidString: idString) else { return nil }
                        return studentsByID[id]
                    }
                    if sl.lesson?.id != targetLesson?.id { sl.lesson = targetLesson; changed = true }
                    let currentIDs = Set(sl.students.map { $0.id })
                    let targetIDs = Set(targetStudents.map { $0.id })
                    if currentIDs != targetIDs {
                        sl.students = targetStudents
                        changed = true
                    }
                    if changed {
                        sl.syncSnapshotsFromRelationships()
                    }
                }

                processed += batch.count
                // Save periodically to avoid holding too many changes in memory
                if changed && processed % batchSize == 0 {
                    context.safeSave()
                    changed = false // Reset for next batch
                }
            }

            // Final save if there are remaining changes
            if changed {
                context.safeSave()
            }
        }
    }

    /// Backfill isPresented flag from givenAt field.
    /// One-time migration: if givenAt is set, isPresented should be true.
    /// Idempotent: guarded by a UserDefaults flag.
    static func backfillIsPresentedIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.isPresentedFromGivenAt.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = 1000
            var changed = false

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    if sl.givenAt != nil && sl.isPresented == false {
                        sl.isPresented = true
                        changed = true
                    }
                }

                if changed && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    changed = false
                }
            }
        }
    }

    /// Backfill scheduledForDay field from scheduledFor.
    /// One-time migration that ensures scheduledForDay matches scheduledFor for all records.
    /// Idempotent: guarded by a UserDefaults flag.
    static func backfillScheduledForDayIfNeeded(using context: ModelContext) async {
        let flagKey = "Backfill.scheduledForDay.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let sls = context.safeFetch(FetchDescriptor<StudentLesson>())
            let batchSize = 1000
            var needsSave = false

            for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                if batchStart % 500 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, sls.count)
                let batch = Array(sls[batchStart..<batchEnd])

                for sl in batch {
                    let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
                    if sl.scheduledForDay != correct {
                        sl.scheduledForDay = correct
                        needsSave = true
                    }
                }

                if needsSave && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                    context.safeSave()
                    needsSave = false
                }
            }
        }
    }

    // MARK: - Presentation-StudentLesson Links

    /// Backfill Presentation.legacyStudentLessonID by linking to matching StudentLessons.
    /// Idempotent: only sets legacyStudentLessonID when it is nil or empty.
    static func backfillPresentationStudentLessonLinks(using context: ModelContext) async {
        let flagKey = "Backfill.presentationStudentLessonLinks.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let presentations = context.safeFetch(FetchDescriptor<Presentation>())
            let studentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())

            let presentationsToBackfill = presentations.filter { presentation in
                guard let legacyID = presentation.legacyStudentLessonID else { return true }
                return legacyID.isEmpty
            }

            guard !presentationsToBackfill.isEmpty else { return }

            let batchSize = 100
            var changed = false

            for batchStart in stride(from: 0, to: presentationsToBackfill.count, by: batchSize) {
                if batchStart % 100 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, presentationsToBackfill.count)
                let batch = Array(presentationsToBackfill[batchStart..<batchEnd])

                for presentation in batch {
                    if let existingID = presentation.legacyStudentLessonID, !existingID.isEmpty {
                        continue
                    }

                    let pLessonID = presentation.lessonID
                    let pStudentIDs = Set(presentation.studentIDs)
                    let pDay = Calendar.current.startOfDay(for: presentation.presentedAt)

                    var candidates: [StudentLesson] = []

                    for sl in studentLessons {
                        let slLessonIDMatch = sl.resolvedLessonID.uuidString == pLessonID || sl.lessonID == pLessonID
                        guard slLessonIDMatch else { continue }

                        let slStudentIDs = Set(sl.studentIDs)
                        let overlap = pStudentIDs.intersection(slStudentIDs)
                        guard overlap.count >= 1 else { continue }

                        let slDay = sl.givenAt.map { Calendar.current.startOfDay(for: $0) }
                        if let slDay {
                            guard slDay == pDay else { continue }
                        }

                        candidates.append(sl)
                    }

                    guard let bestMatch = chooseBestMatch(
                        candidates: candidates,
                        presentation: presentation,
                        pStudentIDs: pStudentIDs
                    ) else {
                        continue
                    }

                    presentation.legacyStudentLessonID = bestMatch.id.uuidString
                    changed = true
                }

                if changed && (batchEnd % batchSize == 0 || batchEnd == presentationsToBackfill.count) {
                    context.safeSave()
                    changed = false
                }
            }

            if changed {
                context.safeSave()
            }
        }
    }

    /// Repairs Presentation.legacyStudentLessonID for existing records that have incorrect or missing links.
    /// Uses strict matching first (exact lessonID + exact studentIDs set match), then falls back to loose matching.
    /// Idempotent: guarded by a UserDefaults flag so it runs once.
    static func repairPresentationStudentLessonLinks_v2(using context: ModelContext) async {
        let flagKey = "Repair.presentationStudentLessonLinks.v2"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let presentations = context.safeFetch(FetchDescriptor<Presentation>())
            let studentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
            let studentLessonByID = Dictionary(studentLessons.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })

            // Pre-build lookup dictionaries for O(1) access instead of O(n) loops per presentation
            // Group StudentLessons by lessonID for fast lookup
            var studentLessonsByLessonID: [String: [StudentLesson]] = [:]
            for sl in studentLessons {
                let resolvedID = sl.resolvedLessonID.uuidString
                let rawID = sl.lessonID
                studentLessonsByLessonID[resolvedID, default: []].append(sl)
                if rawID != resolvedID {
                    studentLessonsByLessonID[rawID, default: []].append(sl)
                }
            }

            let batchSize = 100
            var changed = false

            for batchStart in stride(from: 0, to: presentations.count, by: batchSize) {
                if batchStart % 50 == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, presentations.count)
                let batch = Array(presentations[batchStart..<batchEnd])

                for presentation in batch {
                    // Skip if legacyStudentLessonID already equals an existing StudentLesson.id.uuidString (valid link)
                    if let existingID = presentation.legacyStudentLessonID,
                       !existingID.isEmpty,
                       let matchedSL = studentLessonByID[existingID] {
                        let lessonMatch = presentation.lessonID == matchedSL.resolvedLessonID.uuidString || presentation.lessonID == matchedSL.lessonID
                        let presentationStudentSet = Set(presentation.studentIDs)
                        let slStudentSet = Set(matchedSL.studentIDs)
                        let studentMatch = presentationStudentSet == slStudentSet

                        if lessonMatch && studentMatch {
                            continue
                        }
                    }

                    let pLessonID = presentation.lessonID
                    let pStudentIDs = Set(presentation.studentIDs)
                    let pPresentedAt = presentation.presentedAt

                    var matched: StudentLesson?

                    // Use pre-built dictionary for O(1) lookup instead of O(n) loop
                    let candidatesForLesson = studentLessonsByLessonID[pLessonID] ?? []

                    // PASS 1: Strict matching (exact lessonID match + exact studentIDs set match)
                    let strictCandidates = candidatesForLesson.filter { sl in
                        Set(sl.studentIDs) == pStudentIDs
                    }

                    if !strictCandidates.isEmpty {
                        // Find best match by time difference
                        matched = strictCandidates.min { a, b in
                            let aTime = abs(bestDate(for: a).timeIntervalSince(pPresentedAt))
                            let bTime = abs(bestDate(for: b).timeIntervalSince(pPresentedAt))
                            return aTime < bTime
                        }
                        // Fallback to oldest by creation date if time differences are all equal
                        if matched == nil {
                            matched = strictCandidates.min(by: { $0.createdAt < $1.createdAt })
                        }
                    }

                    // PASS 2: Loose matching (for unmatched presentations)
                    if matched == nil {
                        let looseCandidates: [StudentLesson]
                        if pStudentIDs.isEmpty {
                            looseCandidates = candidatesForLesson
                        } else {
                            looseCandidates = candidatesForLesson.filter { sl in
                                !pStudentIDs.intersection(Set(sl.studentIDs)).isEmpty
                            }
                        }

                        if !looseCandidates.isEmpty {
                            // Prefer same-day candidates
                            let sameDayCandidates = looseCandidates.filter { candidate in
                                guard let givenAt = candidate.givenAt else { return false }
                                return Calendar.current.isDate(givenAt, inSameDayAs: pPresentedAt)
                            }

                            let candidatesToConsider = sameDayCandidates.isEmpty ? looseCandidates : sameDayCandidates

                            // Find best match by time difference
                            matched = candidatesToConsider.min { a, b in
                                let aTime = a.givenAt.map { abs($0.timeIntervalSince(pPresentedAt)) } ?? 0
                                let bTime = b.givenAt.map { abs($0.timeIntervalSince(pPresentedAt)) } ?? 0
                                return aTime < bTime
                            }
                            // Fallback to oldest by creation date
                            if matched == nil {
                                matched = candidatesToConsider.min(by: { $0.createdAt < $1.createdAt })
                            }
                        }
                    }

                    if let matched = matched {
                        presentation.legacyStudentLessonID = matched.id.uuidString
                        changed = true
                    }
                }

                if changed && (batchEnd % batchSize == 0 || batchEnd == presentations.count) {
                    context.safeSave()
                    changed = false
                }
            }

            if changed {
                context.safeSave()
            }
        }
    }

    // MARK: - Note-StudentLesson Links

    /// Backfill Note.studentLesson for notes attached to Presentations with legacyStudentLessonID.
    /// Idempotent: only sets studentLesson when it is nil and a matching StudentLesson exists.
    static func backfillNoteStudentLessonFromPresentation(using context: ModelContext) async {
        let flagKey = "Backfill.noteStudentLessonFromPresentation.v1"
        await MigrationFlag.runIfNeeded(key: flagKey) {
            let allNotes = context.safeFetch(FetchDescriptor<Note>())
            let allStudentLessons = context.safeFetch(FetchDescriptor<StudentLesson>())
            let studentLessonsByID = Dictionary(allStudentLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            var changed = false
            let batchSize = 100

            for batchStart in stride(from: 0, to: allNotes.count, by: batchSize) {
                if batchStart % (batchSize * 5) == 0 {
                    await Task.yield()
                }

                let batchEnd = min(batchStart + batchSize, allNotes.count)
                let batch = Array(allNotes[batchStart..<batchEnd])

                for note in batch {
                    guard let presentation = note.presentation else { continue }

                    if note.studentLesson != nil {
                        continue
                    }

                    guard let legacyIDString = presentation.legacyStudentLessonID,
                          !legacyIDString.isEmpty,
                          let legacyID = UUID(uuidString: legacyIDString) else {
                        continue
                    }

                    guard let studentLesson = studentLessonsByID[legacyID] else {
                        continue
                    }

                    note.studentLesson = studentLesson
                    changed = true
                }

                if changed && (batchEnd % batchSize == 0 || batchEnd == allNotes.count) {
                    context.safeSave()
                    changed = false
                }
            }

            if changed {
                context.safeSave()
            }
        }
    }

    // MARK: - Helper Functions

    /// Helper function to choose the best matching StudentLesson for a Presentation.
    /// Selection criteria:
    /// 1. Highest overlap count wins
    /// 2. Tie-breaker: closest |sl.givenAt - p.presentedAt| if both exist
    /// 3. Final fallback: earliest createdAt
    private static func chooseBestMatch(
        candidates: [StudentLesson],
        presentation: Presentation,
        pStudentIDs: Set<String>
    ) -> StudentLesson? {
        guard !candidates.isEmpty else { return nil }

        let candidatesWithOverlap = candidates.map { sl -> (sl: StudentLesson, overlap: Int) in
            let slStudentIDs = Set(sl.studentIDs)
            let overlap = pStudentIDs.intersection(slStudentIDs).count
            return (sl, overlap)
        }

        let maxOverlap = candidatesWithOverlap.map { $0.overlap }.max() ?? 0
        let topCandidates = candidatesWithOverlap.filter { $0.overlap == maxOverlap }

        if topCandidates.count == 1 {
            return topCandidates[0].sl
        }

        let pDate = presentation.presentedAt
        var bestCandidate: StudentLesson?
        var minTimeDifference: TimeInterval = .greatestFiniteMagnitude

        for (sl, _) in topCandidates {
            if let slDate = sl.givenAt {
                let timeDifference = abs(slDate.timeIntervalSince(pDate))
                if timeDifference < minTimeDifference {
                    minTimeDifference = timeDifference
                    bestCandidate = sl
                }
            }
        }

        if let best = bestCandidate {
            return best
        }

        return topCandidates.min(by: { $0.sl.createdAt < $1.sl.createdAt })?.sl
    }

    /// Helper function to get the best available date from a StudentLesson for time-based matching.
    /// Priority: givenAt > scheduledFor > createdAt
    private static func bestDate(for studentLesson: StudentLesson) -> Date {
        if let givenAt = studentLesson.givenAt {
            return givenAt
        }
        if let scheduledFor = studentLesson.scheduledFor {
            return scheduledFor
        }
        return studentLesson.createdAt
    }

    // MARK: - Run All Relationship Backfills

    /// Runs all relationship backfill migrations in sequence.
    /// Safe to call repeatedly - each migration is idempotent.
    static func runAllRelationshipBackfills(using context: ModelContext) async {
        await backfillRelationshipsIfNeeded(using: context)
        await backfillIsPresentedIfNeeded(using: context)
        await backfillScheduledForDayIfNeeded(using: context)
        await backfillPresentationStudentLessonLinks(using: context)
        await repairPresentationStudentLessonLinks_v2(using: context)
        await backfillNoteStudentLessonFromPresentation(using: context)
    }
}
