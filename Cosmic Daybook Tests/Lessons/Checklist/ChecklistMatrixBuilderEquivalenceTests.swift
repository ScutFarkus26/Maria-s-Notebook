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

        // A confirmed lesson with open work of her own: the next cell is Ready, check first.
        let geometry = (0..<2).map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Geometry \(order)", area: "Math", sequence: "Geometry"
            )
            lesson.orderInSequence = Int64(order)
            return lesson
        }
        lessons.append(contentsOf: geometry)
        let shown = CDLessonAssignment(context: context)
        shown.lessonID = try #require(geometry[0].id).uuidString
        shown.studentIDs = [students[1].cloudKitKey]
        shown.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
        shown.confirmStudent(try #require(students[1].id))
        let open = CoreDataTestHelpers.seedWorkModel(
            in: context, studentID: try #require(students[1].id), lessonID: try #require(geometry[0].id)
        )
        open.status = .active
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
        let batched = ClassGridEngine.buildMatrix(students: students, lessons: lessons, context: context)
        #expect(batched.count == students.count)
        #expect(batched == legacy)

        // Sanity: the seed actually produced every kind of cell the comparison should cover.
        let cells = batched.values.flatMap(\.values)
        #expect(cells.contains { $0.isPresented })
        #expect(cells.contains { $0.isScheduled })
        #expect(cells.contains { $0.contractID != nil })
        #expect(cells.contains { $0.blockingReason == .prerequisiteNotPresented })
        #expect(cells.contains { $0.blockingReason != .none && $0.blockingReason != .prerequisiteNotPresented })
        #expect(cells.contains { !$0.checkFirstReasons.isEmpty })
    }

    @Test func emptyLessonsGiveEmptyMatrix() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let student = CoreDataTestHelpers.seedStudent(in: context)
        #expect(ClassGridEngine.buildMatrix(students: [student], lessons: [], context: context).isEmpty)
    }
}

/// The builder as it was before the batched fetches (2026-09-22): one fetch per
/// lesson (and per giving), calling the shared `buildCellState`. Its rules
/// follow the builder's since bug hunt 2026-10-11 #17/#18: a cell reads the
/// work that counts as the child's (`WorkGrouping.visibleWork`, row by row,
/// against the builder's batched `WorkVisibility`). Since 2026-10-18 "Not yet" and
/// "Ready, check first" are the one readiness rule (`ReadyForNextEngine.readiness(of:)`),
/// read here one cell at a time.
@MainActor
private enum LegacyMatrixBuilder {
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
        for student in students {
            var studentRow: [UUID: StudentChecklistRowState] = [:]
            let studentKey = student.cloudKitKey
            let studentUUID = student.id ?? UUID()
            for lesson in lessons {
                guard let lessonID = lesson.id else { continue }
                let lessonIDString = lessonID.uuidString
                let studentLAs = (lasByLessonID[lessonIDString] ?? []).filter { $0.studentIDs.contains(studentKey) }
                let studentWorks = WorkGrouping.visibleWork(
                    for: studentUUID, among: worksByLessonID[lessonIDString] ?? [], in: context
                )
                var readiness = (blocking: BlockingReason.none, checkFirst: [String]())
                if !studentLAs.contains(where: { $0.isPresented }), let preceding = precedingLessonMap[lessonID] {
                    readiness = cellReadiness(precedingLesson: preceding, studentID: studentUUID, context: context)
                }
                studentRow[lessonID] = ClassGridEngine.buildCellState(
                    lesson: lesson, studentLAs: studentLAs, studentWorkModels: studentWorks,
                    calendar: calendar, today: today, blockingReason: readiness.blocking,
                    checkFirstReasons: readiness.checkFirst
                )
            }
            guard let studentID = student.id else { continue }
            newMatrix[studentID] = studentRow
        }
        return newMatrix
    }

    /// One cell's readiness, read on its own: the record, work and recall checks of the
    /// lesson before, for this one child.
    private static func cellReadiness(
        precedingLesson: CDLesson, studentID: UUID, context: NSManagedObjectContext
    ) -> (blocking: BlockingReason, checkFirst: [String]) {
        let lessonID = precedingLesson.id?.uuidString ?? ""
        let student = studentID.uuidString
        let index = PresentationRecordIndex(lessonIDs: [lessonID], students: [student], in: context)
        guard let given = index.given(student: student, lesson: lessonID) else {
            return (.prerequisiteNotPresented, [])
        }
        let record = PreviousLessonRecord(
            pairs: [PreviousLessonRecord.Pair(studentID: student, lessonID: lessonID)], in: context
        )
        let verdict = ReadyForNextEngine.readiness(of: record.status(student: student, lesson: lessonID, given: given))
        switch verdict.tier {
        case .notReady: return (.confirmationRequired, [])
        case .almostReady: return (.none, verdict.reasons)
        case .ready: return (.none, [])
        }
    }
}
