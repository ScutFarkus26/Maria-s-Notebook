import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins that the batched matrix builder (one `lessonID IN` fetch per entity,
/// prefetched participants, memoised rules) produces exactly the matrix the
/// per-lesson-fetch builder did, on a varied seeded store.
@MainActor
struct ChecklistMatrixBuilderEquivalenceTests {

    /// Small deterministic generator so the seeded store is the same every run.
    private struct LCG {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    @Test func batchedBuilderMatchesLegacyBuilder() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        var rng = LCG(state: 42)

        let students = (0..<7).map { index in
            CoreDataTestHelpers.seedStudent(in: context, firstName: "S\(index)", lastName: "L\(index)")
        }
        var lessons: [CDLesson] = []
        for (seqIndex, sequence) in ["Counting", "Decimal", "Fractions"].enumerated() {
            for order in 0..<5 {
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "\(sequence) \(order)", area: "Math", sequence: sequence
                )
                lesson.orderInSequence = Int64(order)
                if seqIndex == 2 && order == 1 { lesson.practiceOverride = .no }
                if seqIndex == 2 && order == 2 {
                    lesson.practiceOverride = .yes
                    lesson.confirmationOverride = .no
                }
                lessons.append(lesson)
            }
        }
        // Group settings for one sequence; stored in a different case to exercise ==[c].
        let settings = CDLessonSequenceSettings(context: context)
        settings.area = "math"
        settings.sequence = "decimal"
        settings.requiresPractice = false
        settings.requiresTeacherConfirmation = true

        let statuses: [WorkStatus] = [.active, .review, .mastered, .keepPracticing, .incomplete, .done]
        for lesson in lessons {
            let lessonID = try #require(lesson.id)
            for _ in 0..<rng.next(4) {
                let la = CDLessonAssignment(context: context)
                la.lessonID = lessonID.uuidString
                let members = students.filter { _ in rng.next(3) == 0 }
                la.studentIDs = members.map(\.cloudKitKey)
                switch rng.next(3) {
                case 0:
                    la.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
                    if let first = members.first, rng.next(2) == 0 { la.confirmStudent(try #require(first.id)) }
                case 1: la.schedule(onDay: Date(timeIntervalSince1970: 1_790_000_000))
                default: break
                }
            }
            for _ in 0..<rng.next(4) {
                let work = CDWorkModel(context: context)
                work.lessonID = lessonID.uuidString
                work.status = statuses[rng.next(statuses.count)]
                work.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(rng.next(10_000_000)))
                if rng.next(2) == 0 { work.lastTouchedAt = Date(timeIntervalSince1970: 1_750_000_000) }
                for student in students where rng.next(3) == 0 {
                    let participant = CDWorkParticipantEntity(context: context)
                    participant.studentID = student.cloudKitKey
                    participant.work = work
                }
            }
        }
        try context.save()

        // Another saved presentation, then compare. (Rows are compared on a
        // clean context: an unsorted fetch has no defined order once the
        // context holds unsaved changes, for the old per-lesson reads as much
        // as for the batched one, and `.first` picks from that order.)
        let extra = CDLessonAssignment(context: context)
        extra.lessonID = try #require(lessons[3].id).uuidString
        extra.studentIDs = [students[0].cloudKitKey]
        extra.markPresented()
        try context.save()

        let legacy = LegacyMatrixBuilder.buildMatrix(students: students, lessons: lessons, context: context)
        let batched = ChecklistMatrixBuilder.buildMatrix(students: students, lessons: lessons, context: context)
        #expect(batched.count == students.count)
        #expect(batched == legacy)

        // Sanity: the seed actually produced every kind of cell the comparison should cover.
        let cells = batched.values.flatMap(\.values)
        #expect(cells.contains { $0.isPresented })
        #expect(cells.contains { $0.isScheduled })
        #expect(cells.contains { $0.contractID != nil })
        #expect(cells.contains { $0.blockingReason == .prerequisiteNotPresented })
        #expect(cells.contains { $0.blockingReason != .none && $0.blockingReason != .prerequisiteNotPresented })
    }

    @Test func emptyLessonsGiveEmptyMatrix() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        #expect(ChecklistMatrixBuilder.buildMatrix(students: [student], lessons: [], context: context).isEmpty)
    }
}

/// The builder as it was before the batched fetches (2026-09-22), kept verbatim
/// apart from calling the shared `buildCellState`.
@MainActor
private enum LegacyMatrixBuilder {
    // swiftlint:disable:next function_body_length
    static func buildMatrix(
        students: [CDStudent],
        lessons: [CDLesson],
        context: NSManagedObjectContext
    ) -> [UUID: [UUID: StudentChecklistRowState]] {
        let lessonIDStrings = Set(lessons.compactMap { $0.id?.uuidString })
        guard !lessonIDStrings.isEmpty else { return [:] }
        var lasByLessonID: [String: [CDLessonAssignment]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor: NSFetchRequest<CDLessonAssignment> = CDFetchRequest(CDLessonAssignment.self)
            descriptor.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
            lasByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }
        var worksByLessonID: [String: [CDWorkModel]] = [:]
        for lessonIDString in lessonIDStrings {
            let descriptor: NSFetchRequest<CDWorkModel> = CDFetchRequest(CDWorkModel.self)
            descriptor.predicate = NSPredicate(format: "lessonID == %@", lessonIDString as CVarArg)
            worksByLessonID[lessonIDString] = context.safeFetch(descriptor)
        }
        var newMatrix: [UUID: [UUID: StudentChecklistRowState]] = [:]
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: Date())
        let precedingLessonMap = BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)
        var progressionRulesMap: [UUID: LessonProgressionRules.ResolvedRules] = [:]
        for (lessonID, preceding) in precedingLessonMap {
            progressionRulesMap[lessonID] = LessonProgressionRules.resolve(for: preceding, context: context)
        }
        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentKey = student.cloudKitKey
            let studentUUID = student.id ?? UUID()
            for lesson in lessons {
                guard let lessonID = lesson.id else { continue }
                let lessonIDString = lessonID.uuidString
                let studentLAs = (lasByLessonID[lessonIDString] ?? []).filter { $0.studentIDs.contains(studentKey) }
                let studentWorks = (worksByLessonID[lessonIDString] ?? []).filter { work in
                    let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
                    return participants.contains { $0.studentID == studentKey }
                }
                let blockingReason: BlockingReason
                if !studentLAs.contains(where: { $0.isPresented }), let preceding = precedingLessonMap[lessonID] {
                    blockingReason = computeBlockingReason(
                        precedingLesson: preceding, rules: progressionRulesMap[lessonID],
                        studentID: studentUUID, studentKey: studentKey,
                        lasByLessonID: lasByLessonID, worksByLessonID: worksByLessonID
                    )
                } else {
                    blockingReason = .none
                }
                studentRow[lessonID] = ChecklistMatrixBuilder.buildCellState(
                    lesson: lesson, studentLAs: studentLAs, studentWorkModels: studentWorks,
                    calendar: calendar, today: today, blockingReason: blockingReason
                )
            }
            guard let studentID = student.id else { continue }
            newMatrix[studentID] = studentRow
        }
        return newMatrix
    }

    // swiftlint:disable:next function_parameter_count
    private static func computeBlockingReason(
        precedingLesson: CDLesson,
        rules: LessonProgressionRules.ResolvedRules?,
        studentID: UUID,
        studentKey: String,
        lasByLessonID: [String: [CDLessonAssignment]],
        worksByLessonID: [String: [CDWorkModel]]
    ) -> BlockingReason {
        guard let rules, rules.requiresPractice || rules.requiresTeacherConfirmation else { return .none }
        let precedingIDStr = precedingLesson.id?.uuidString ?? ""
        let precedingLAs = lasByLessonID[precedingIDStr] ?? []
        guard let presentedLA = precedingLAs.first(where: { $0.isPresented && $0.studentIDs.contains(studentKey) })
        else { return .prerequisiteNotPresented }
        var needsPractice = false
        var needsConfirmation = false
        if rules.requiresPractice {
            let studentWorks = (worksByLessonID[precedingIDStr] ?? []).filter { work in
                let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
                return participants.contains { $0.studentID == studentKey }
            }
            let allComplete = !studentWorks.isEmpty && studentWorks.allSatisfy { $0.status.isClosed }
            if studentWorks.isEmpty || !allComplete { needsPractice = true }
        }
        if rules.requiresTeacherConfirmation, !presentedLA.isStudentConfirmed(studentID) {
            needsConfirmation = true
        }
        if needsPractice && needsConfirmation { return .practiceAndConfirmation }
        if needsPractice { return .practiceRequired }
        if needsConfirmation { return .confirmationRequired }
        return .none
    }
}
