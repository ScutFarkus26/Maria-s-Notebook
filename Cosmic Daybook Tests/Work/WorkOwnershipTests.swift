import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Domain logic review 2026-11-20 (plan "Domain logic fixes", Phase 5): whose
// a work row is has one rule built on `assignmentID` and `isSharedRow` (R22),
// older rows get both from a fill that runs at launch and after a restore,
// work is given one way (A3), and a shared row closes with its last child
// (R23). The rest of the phase's rules are in WorkRulesTests.swift.

@Suite("Work ownership and assignments (domain logic, Phase 5)")
@MainActor
struct WorkOwnershipTests {

    private func day(_ offset: Int) -> Date {
        AppCalendar.addingDays(offset, to: AppCalendar.startOfDay(Date()))
    }

    /// A row as a build before schema 25 left it: no assignment, naming `named`.
    private func legacyRow(
        owner: UUID?, named: [UUID], lesson: UUID, title: String = "Checkerboard",
        in context: NSManagedObjectContext
    ) -> CDWorkModel {
        let row = CoreDataTestHelpers.seedWorkModel(in: context, title: title, lessonID: lesson)
        row.id = UUID()
        row.studentID = owner?.uuidString ?? ""
        for child in named {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = row
        }
        return row
    }

    // MARK: - The rule

    @Test("A row is hers when she owns it, or is on it with no copy of her own")
    func theRule() {
        let maya = UUID(), eli = UUID(), noa = UUID()
        func counts(_ child: UUID, owner: UUID?, shared: Bool = false, ownsACopy: Bool = false) -> Bool {
            WorkOwnership.counts(
                for: child, ownerID: owner, namedIDs: [eli, maya], isSharedRow: shared, ownsACopy: ownsACopy
            )
        }
        // Her own copy of work given to a group.
        #expect(counts(maya, owner: maya, ownsACopy: true))
        // A classmate's copy names her without being hers: she has her own.
        #expect(!counts(maya, owner: eli, ownsACopy: true))
        // A classmate's row she is on, with none of her own beside it.
        #expect(counts(maya, owner: eli))
        // A shared row counts for everyone on it, and for nobody else.
        #expect(counts(maya, owner: eli, shared: true, ownsACopy: true))
        #expect(!counts(noa, owner: eli, shared: true))
        // Offered work nobody owns is its claimers'.
        #expect(counts(maya, owner: nil))
    }

    @Test("A shared project row beside her own work counts for her, in readiness and in her meeting")
    func sharedRowCountsBesideHerOwn() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), eli = UUID(), lesson = UUID()
        let own = try WorkRepository(context: context).createWork(
            studentID: maya, lessonID: lesson, title: "Her own", saveImmediately: false
        )
        let project = legacyRow(owner: eli, named: [eli, maya], lesson: lesson, title: "Poster", in: context)
        project.sourceContextType = .projectSession
        #expect(CoreDataTestHelpers.save(context))

        // Readiness used to drop the shared row whenever she owned anything.
        let gating = BlockingAlgorithmEngine.gatingWork(for: maya, among: [own, project])
        #expect(Set(gating.map(\.objectID)) == [own.objectID, project.objectID])
        // The meeting read only the rows she owned.
        let stats = MeetingWorkSnapshotHelper.computeWorkStats(
            for: maya, allWorkModels: [own, project], workOverdueDays: 14
        )
        #expect(Set(stats.open.map(\.objectID)) == [own.objectID, project.objectID])
        #expect(WorkOwnership.students(of: project, in: context) == [eli, maya])
        #expect(WorkOwnership.students(of: own, in: context) == [maya])
    }

    // MARK: - The fill

    @Test("The launch fill gives linked copies one assignmentID, and marks the rows children share")
    func fillStampsOlderRows() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), eli = UUID(), lesson = UUID()
        let mayas = legacyRow(owner: maya, named: [maya, eli], lesson: lesson, in: context)
        let elis = legacyRow(owner: eli, named: [eli, maya], lesson: lesson, in: context)
        let shared = legacyRow(owner: maya, named: [maya, eli], lesson: UUID(), title: "Poster", in: context)
        let project = legacyRow(owner: maya, named: [maya], lesson: UUID(), title: "Offered", in: context)
        project.sourceContextType = .projectSession
        let single = legacyRow(owner: maya, named: [maya], lesson: UUID(), title: "Hers", in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(mayas.assignmentID == nil)

        let changed = WorkAssignmentFill.run(in: context)

        #expect(changed == 5)
        let copyIDs = try [#require(mayas.id), #require(elis.id)].map(\.uuidString)
        #expect(mayas.assignmentID == copyIDs.min(), "worked out from the rows, so every device agrees")
        #expect(elis.assignmentID == mayas.assignmentID)
        #expect(!mayas.isSharedRow)
        #expect(!elis.isSharedRow)
        #expect(shared.isSharedRow, "one row, two children, no copies beside it")
        #expect(shared.assignmentID == shared.id?.uuidString)
        #expect(project.isSharedRow, "project work is shared by construction, whoever has claimed it so far")
        #expect(!single.isSharedRow)
        #expect(single.assignmentID == single.id?.uuidString)
        #expect(WorkAssignmentFill.run(in: context) == 0, "it keys on the nil, so a second run finds nothing")
    }

    @Test("Once filled, copies are matched by their assignment, not by the guess")
    func filledCopiesMatchByAssignment() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), eli = UUID(), lesson = UUID()
        let mayas = legacyRow(owner: maya, named: [maya, eli], lesson: lesson, in: context)
        let elis = legacyRow(owner: eli, named: [eli, maya], lesson: lesson, in: context)
        WorkAssignmentFill.run(in: context)
        // What broke the guess: one copy renamed, made on another day, of another kind.
        elis.title = "Renamed"
        elis.createdAt = day(-30)
        elis.kind = .research
        #expect(CoreDataTestHelpers.save(context))

        let group = WorkGrouping.group(containing: mayas, in: context)
        #expect(Set(group.members.map(\.objectID)) == [mayas.objectID, elis.objectID])
        #expect(group.shape == .linkedCopies(total: 2))
        let ownership = WorkOwnership.Reader(rows: [mayas, elis])
        #expect(ownership.isWork(mayas, of: maya))
        #expect(!ownership.isWork(elis, of: maya), "a classmate's copy is never hers")
    }

    @Test("The fill waits out the first download, and runs after a restore")
    func fillWaitsAndRunsAfterRestore() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let row = legacyRow(owner: UUID(), named: [], lesson: UUID(), in: context)
        #expect(CoreDataTestHelpers.save(context))

        // A half-downloaded store: a copy's siblings may not be here yet.
        #expect(WorkAssignmentFill.runIfDue(using: context, firstDownloadPending: true) == nil)
        #expect(row.assignmentID == nil)

        let fill = try #require(BackupService.afterRestoreFills.first { $0.name == "work assignments" })
        fill.run(context, 46)
        #expect(row.assignmentID == row.id?.uuidString)
        context.rollback()

        #expect(WorkAssignmentFill.runIfDue(using: context, firstDownloadPending: false) == 1)
        #expect(!context.hasChanges, "the launch run saves what it filled")
    }

    // MARK: - A3: giving work

    @Test("Work given to a group: one assignment, a copy each, the check-in on a school day")
    func assignmentServiceMakesLinkedCopies() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), eli = UUID()
        let calendar = AppCalendar.shared
        // The next Saturday: Quick New Work used to put the check-in on it.
        let saturday = try #require((1...7).map { day($0) }.first { calendar.component(.weekday, from: $0) == 7 })
        let friday = day(20)

        let assigned = try WorkAssignmentService(context: context).create(.init(
            lessonID: UUID(), studentIDs: [maya, eli], title: "Stamp game", dueDate: friday,
            checkIn: .init(day: saturday, purpose: "progressCheck")
        ))

        #expect(assigned.works.count == 2)
        let mayas = try #require(assigned.works.first)
        let elis = try #require(assigned.works.last)
        #expect(mayas.assignmentID != nil)
        #expect(mayas.assignmentID == elis.assignmentID)
        #expect(!mayas.isSharedRow)
        #expect(Set(WorkGrouping.studentIDs(of: mayas)) == [maya, eli], "each copy names the other, once")
        #expect(WorkLogService.participants(of: mayas).count == 2)
        #expect(WorkGrouping.group(containing: mayas, in: context).shape == .linkedCopies(total: 2))

        let landed = try #require(assigned.checkInDay)
        #expect(assigned.checkInAskedFor == saturday)
        #expect(landed > saturday)
        #expect(![1, 7].contains(calendar.component(.weekday, from: landed)), "not on the weekend")
        for work in assigned.works {
            #expect(WorkCheckInService.nextCheckDay(of: work, in: context) == landed)
            #expect(work.dueAt == friday, "the due date is the guide's, not the check day")
        }
    }

    // MARK: - R23 with mastery

    @Test("Mastery on a row she shares finishes her part; the last child's closes it")
    func markOnSharedRowFinishesHerPart() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), eli = UUID(), lesson = UUID()
        // A group row with no owner, as the Checklist's older builds made.
        let shared = legacyRow(owner: nil, named: [maya, eli], lesson: lesson, in: context)
        for child in [maya, eli] {
            let record = CDLessonPresentation(context: context)
            record.studentID = child.uuidString
            record.lessonID = lesson.uuidString
            record.presentedAt = day(-7)
        }
        #expect(CoreDataTestHelpers.save(context))

        let first = MasteryMarking.mark([maya], lessonID: lesson, in: context)

        #expect(first.changed == [maya])
        #expect(first.closedWork == 0)
        #expect(shared.status.isOpen, "Eli is still working, and nobody marked him")
        #expect(shared.participant(for: maya)?.completedAt != nil)
        #expect(shared.participant(for: eli)?.completedAt == nil)

        let second = MasteryMarking.mark([eli], lessonID: lesson, in: context)

        #expect(second.closedWork == 1)
        #expect(shared.status == .done, "closed as Finished: a verdict for the row, not a mark for each child")
        let records = try WorkCompletionService.records(for: try #require(shared.id), in: context)
        #expect(records.map(\.studentID).sorted() == [maya, eli].map(\.uuidString).sorted(), "one record each")
    }

    // MARK: - R14: the ladder's one input

    @Test("Practice and the stored state climb the ladder on every screen")
    func ladderReadsPracticeAndTheStoredState() throws {
        let presented = LadderInput(isPresented: true)
        #expect(ChecklistDisplayStatus.resolve(presented) == .presented)
        var practiced = presented
        practiced.practiceSessions = 1
        #expect(ChecklistDisplayStatus.resolve(practiced) == .practicing)
        // The recap's pill stores a state; it is a floor, not a ceiling.
        var stored = presented
        stored.storedState = .practicing
        #expect(ChecklistDisplayStatus.resolve(stored) == .practicing)
        stored.storedState = .readyForAssessment
        #expect(ChecklistDisplayStatus.resolve(stored) == .reviewing)
        stored.isMastered = true
        #expect(ChecklistDisplayStatus.resolve(stored) == .mastered)

        // The timeline and the Checklist cell read the same two facts.
        #expect(LessonNodeStatus.resolve(
            isPresented: true, scheduledFor: nil, isMastered: false, workStatuses: [], practiceSessions: 3
        ) == .reviewing)
        #expect(LessonNodeStatus.resolve(
            isPresented: true, scheduledFor: nil, isMastered: false, workStatuses: [], storedState: .practicing
        ) == .practicing)
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        lesson.id = UUID()
        let cell = ClassGridEngine.buildCellState(
            lesson: lesson, studentLAs: [], studentWorkModels: [], calendar: AppCalendar.shared, today: day(0),
            ladder: .init(practiceSessions: 1, storedState: nil)
        )
        #expect(cell.displayStatus == .practicing)
    }

    @Test("The ladder's evidence: finished practice on her work, and the furthest stored state")
    func ladderEvidenceReadsTheStore() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let maya = UUID(), lesson = UUID()
        let work = legacyRow(owner: maya, named: [maya], lesson: lesson, in: context)
        PracticeCheckIns.record(PracticeRecord(date: day(-2), minutes: 10), on: work, in: context)
        CDWorkCheckIn.make(for: work, on: day(3), purpose: PracticeCheckIns.purpose, in: context)
        for state in [LessonPresentationState.practicing, .readyForAssessment, .presented] {
            let record = CDLessonPresentation(context: context)
            record.studentID = maya.uuidString
            record.lessonID = lesson.uuidString
            record.state = state
        }
        #expect(CoreDataTestHelpers.save(context))

        let evidence = LadderEvidence(lessonIDs: [lesson.uuidString], in: context)
        let entry = evidence.entry(lesson: lesson.uuidString, student: maya.uuidString)

        #expect(entry.practiceSessions == 1, "the practice still on the calendar isn't one yet")
        #expect(entry.storedState == .readyForAssessment)
        #expect(evidence.entry(lesson: lesson.uuidString, student: UUID().uuidString) == .init())
    }
}
