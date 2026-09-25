import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// class_curriculum_map builds only the cells of the lesson (or area) it was
// asked about, and the loader brings each work row's participants in with the
// row. Neither may change a cell, so neither changes what the two
// curriculum-map tools print.

@Suite("Curriculum map scoped reads")
@MainActor
struct CurriculumMapScopedReadsTests {

    // MARK: - Fixtures

    private let ora = UUID()
    private let dalia = UUID()
    private let etty = UUID()

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func lesson(_ name: String, area: String, sequence: String, order: Int) -> CurriculumLessonRef {
        CurriculumLessonRef(
            id: UUID(), name: name, area: area, sequence: sequence, section: "", orderInSequence: order,
            sortIndex: order, greatLessonRaw: nil, isStory: false, isKeyLesson: false
        )
    }

    private func work(
        _ lesson: CurriculumLessonRef, _ students: [UUID], _ status: WorkStatus, assigned: String
    ) -> CurriculumWorkRef {
        CurriculumWorkRef(
            id: UUID(), lessonID: lesson.id, studentIDs: students, statusRaw: status.rawValue,
            assignedAt: day(assigned), completedAt: status.isClosed ? day(assigned) : nil,
            lastTouchedAt: day(assigned)
        )
    }

    private struct Seeded {
        let input: CurriculumMapInput
        let laws: CurriculumLessonRef
        let checkerboard: CurriculumLessonRef
        let cell: CurriculumLessonRef
        let untouched: CurriculumLessonRef
    }

    /// Three children across two areas: a regiven group presentation with a
    /// confirmation, doubled mastery rows, group work, practice sessions that
    /// span two lessons in two areas and one on a peer's work, and recalls.
    private func seeded() -> Seeded {
        let laws = lesson("Commutative Law", area: "Math", sequence: "Laws", order: 0)
        let distributive = lesson("Distributive Law", area: "Math", sequence: "Laws", order: 1)
        let checkerboard = lesson("Checkerboard", area: "Math", sequence: "Multiplication", order: 0)
        let cell = lesson("The Cell", area: "Biology", sequence: "Life", order: 0)
        let untouched = lesson("Parts of the Leaf", area: "Biology", sequence: "Botany", order: 0)

        var input = CurriculumMapInput(lessons: [laws, distributive, checkerboard, cell, untouched])
        input.presentations = [
            CurriculumPresentationRef(id: UUID(), lessonID: laws.id, studentIDs: [ora, dalia],
                                      presentedAt: day("2026-02-12"), confirmedStudentIDs: [dalia]),
            CurriculumPresentationRef(id: UUID(), lessonID: laws.id, studentIDs: [ora],
                                      presentedAt: day("2026-03-01"), confirmedStudentIDs: []),
            CurriculumPresentationRef(id: UUID(), lessonID: checkerboard.id, studentIDs: [etty],
                                      presentedAt: nil, confirmedStudentIDs: []),
            CurriculumPresentationRef(id: UUID(), lessonID: cell.id, studentIDs: [ora, etty],
                                      presentedAt: day("2026-01-10"), confirmedStudentIDs: [])
        ]
        input.masteries = [
            CurriculumMasteryRef(id: UUID(), studentID: dalia, lessonID: laws.id, isMastered: true,
                                 presentedAt: day("2026-02-12"), masteredAt: day("2026-04-02"),
                                 lastObservedAt: day("2026-04-02")),
            CurriculumMasteryRef(id: UUID(), studentID: dalia, lessonID: laws.id, isMastered: false,
                                 presentedAt: day("2026-02-12"), masteredAt: nil, lastObservedAt: day("2026-05-01")),
            CurriculumMasteryRef(id: UUID(), studentID: etty, lessonID: distributive.id, isMastered: false,
                                 presentedAt: day("2025-12-01"), masteredAt: nil, lastObservedAt: nil)
        ]
        let groupWork = work(laws, [ora, dalia], .review, assigned: "2026-02-13")
        let soloWork = work(checkerboard, [etty], .active, assigned: "2026-03-02")
        let biologyWork = work(cell, [ora], .mastered, assigned: "2026-01-11")
        input.work = [groupWork, soloWork, biologyWork]
        input.practice = [
            CurriculumPracticeRef(id: UUID(), date: day("2026-02-14"), studentIDs: [ora, dalia],
                                  workIDs: [groupWork.id, biologyWork.id]),
            CurriculumPracticeRef(id: UUID(), date: day("2026-02-15"), studentIDs: [ora], workIDs: [groupWork.id]),
            CurriculumPracticeRef(id: UUID(), date: day("2026-02-16"), studentIDs: [ora], workIDs: [groupWork.id]),
            CurriculumPracticeRef(id: UUID(), date: nil, studentIDs: [etty, dalia], workIDs: [soloWork.id])
        ]
        input.recalls = [
            CurriculumRecallRef(id: UUID(), studentID: ora, lessonID: laws.id, outcome: .shaky,
                                checkedAt: day("2026-04-01")),
            CurriculumRecallRef(id: UUID(), studentID: ora, lessonID: laws.id, outcome: .retained,
                                checkedAt: day("2026-05-01")),
            CurriculumRecallRef(id: UUID(), studentID: etty, lessonID: cell.id, outcome: .forgotten,
                                checkedAt: nil)
        ]
        return Seeded(input: input, laws: laws, checkerboard: checkerboard, cell: cell, untouched: untouched)
    }

    /// The old path: the whole class's grid, then only the lessons in scope.
    private func wholeGrid(
        _ input: CurriculumMapInput, restrictedTo lessonIDs: Set<UUID>
    ) -> [UUID: [UUID: CurriculumCell]] {
        CurriculumMapEngine.cells(input: input)
            .mapValues { byLesson in byLesson.filter { lessonIDs.contains($0.key) } }
            .filter { !$0.value.isEmpty }
    }

    // MARK: - Lesson-scoped cells

    @Test("Cells built for the lessons in scope equal the whole grid's cells for them")
    func scopedCellsMatchTheWholeGrid() {
        let seeded = seeded()
        let input = seeded.input
        let biology = Set(input.lessons.filter { $0.area == "Biology" }.map(\.id))
        let math = Set(input.lessons.filter { $0.area == "Math" }.map(\.id))
        let scopes: [Set<UUID>] = [
            [seeded.laws.id], [seeded.checkerboard.id], [seeded.cell.id], [seeded.untouched.id],
            biology, math, Set(input.lessons.map(\.id)), []
        ]

        for scope in scopes {
            let scoped = CurriculumMapEngine.cells(input: input, lessons: scope)
            #expect(scoped == wholeGrid(input, restrictedTo: scope))
        }
        // The fixture reaches every rung, so the equality above is not vacuous.
        let lawsCells = CurriculumMapEngine.cells(input: input, lessons: [seeded.laws.id])
        #expect(lawsCells[dalia]?[seeded.laws.id]?.state == .mastered)
        #expect(lawsCells[ora]?[seeded.laws.id]?.state == .repeated)
        #expect(lawsCells[ora]?[seeded.laws.id]?.practiceCount == 3)
        #expect(CurriculumMapEngine.cells(input: input, lessons: [seeded.cell.id])[ora]?[seeded.cell.id]?.state
            == .repeated)
        #expect(CurriculumMapEngine.cells(input: input, lessons: [seeded.untouched.id]).isEmpty)
    }

    // MARK: - Work participants

    private struct WorkRoster {
        let owner: UUID
        let participants: [UUID]
    }

    /// Thirty work rows with two participants each, saved to the SQLite store
    /// and read back on a fresh context, so no row is registered beforehand.
    private func savedWorkStore() throws -> (context: NSManagedObjectContext, rosters: [UUID: WorkRoster]) {
        let writer = try CoreDataTestHelpers.makeSplitStoreContext()
        var rosters: [UUID: WorkRoster] = [:]
        for index in 0..<30 {
            let owner = UUID()
            let work = CoreDataTestHelpers.seedWorkModel(
                in: writer, title: "Work \(index)", studentID: owner, lessonID: UUID()
            )
            var participants: [UUID] = []
            for _ in 0..<2 {
                let participant = CDWorkParticipantEntity(context: writer)
                let studentID = UUID()
                participant.studentID = studentID.uuidString
                participant.work = work
                participants.append(studentID)
            }
            rosters[try #require(work.id)] = WorkRoster(owner: owner, participants: participants)
        }
        #expect(CoreDataTestHelpers.save(writer))
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = writer.persistentStoreCoordinator
        return (reader, rosters)
    }

    @Test("The loader's work fetch brings every row's participants with it")
    func workFetchPrefetchesParticipants() throws {
        let context = try savedWorkStore().context

        // Before: the same fetch without prefetching leaves every row's
        // participants as a fault — one SELECT per row when the loader reads it.
        let plain = CDFetchRequest(CDWorkModel.self)
        plain.fetchBatchSize = 200
        let unprefetched = try context.fetch(plain)
        #expect(unprefetched.count == 30)
        #expect(unprefetched.filter { $0.hasFault(forRelationshipNamed: "participants") }.count == 30)

        context.reset()
        let request = CurriculumMapLoader.workRequest()
        #expect(request.relationshipKeyPathsForPrefetching == ["participants"])
        let prefetched = try context.fetch(request)
        #expect(prefetched.count == 30)
        #expect(prefetched.filter { $0.hasFault(forRelationshipNamed: "participants") }.isEmpty)
    }

    @Test("Each work ref still lists its owner first, then its participants")
    func snapshotWorkRefsUnchanged() throws {
        let (context, rosters) = try savedWorkStore()
        let refs = CurriculumMapLoader.snapshot(in: context).work
        #expect(refs.count == 30)
        for ref in refs {
            let roster = try #require(rosters[ref.id])
            #expect(ref.studentIDs.count == 3)
            #expect(ref.studentIDs.first == roster.owner)
            #expect(Set(ref.studentIDs.dropFirst()) == Set(roster.participants))
        }
    }
}
