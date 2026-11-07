import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Siri, Restock and Schedule findings of the 2026-11-03 bugs and
// efficiency hunt (docs/Reviews/Daybook Assistant bugs and efficiency
// 2026-11-03.md, #7, #25 to #31). Siri's Undo test is in `AssistantSiriTests`
// below, which runs one test at a time: it uses the app's own Late and undo
// memories in standard defaults.
@Suite("Daybook Assistant fixes 2026-11-03 (SR)")
@MainActor
struct AssistantFix1103SR {

    private static let viewOnlyKey = ClassroomPermissions.viewOnlyKey

    /// A stack with the classroom share's store beside the first one, as
    /// on a phone that has joined.
    private struct TwoStores {
        let stack: CoreDataStack
        let shared: NSPersistentStore
        let own: NSPersistentStore
    }

    private static func twoStores() throws -> TwoStores {
        let stack = try AssistantTestSupport.makeStack()
        let coordinator = try #require(stack.viewContext.persistentStoreCoordinator)
        let shared = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.sharedConfiguration,
            at: URL(fileURLWithPath: "/dev/null/shared-\(UUID().uuidString)")
        )
        let own = try #require(coordinator.persistentStores.first { $0 !== shared })
        return TwoStores(stack: stack, shared: shared, own: own)
    }

    // MARK: - #7

    // Siri could open the app cold and change Restock before the share's
    // permission was read, finding "can change" every time.
    @Test("View only is kept on the phone, and setting it false (a Leave) forgets it")
    func viewOnlyIsKept() {
        let was = ClassroomPermissions.shareIsViewOnly
        let stored = UserDefaults.standard.object(forKey: Self.viewOnlyKey)
        defer {
            ClassroomPermissions.shareIsViewOnly = was
            UserDefaults.standard.set(stored, forKey: Self.viewOnlyKey)
        }
        ClassroomPermissions.shareIsViewOnly = true
        #expect(UserDefaults.standard.bool(forKey: Self.viewOnlyKey))
        #expect(AssistantRestockModel.refusedByShare)

        ClassroomPermissions.shareIsViewOnly = false
        #expect(UserDefaults.standard.object(forKey: Self.viewOnlyKey) == nil)
        #expect(!AssistantRestockModel.refusedByShare)
    }

    // MARK: - #25

    @Test("Siri's saves file every classroom record they insert, Siri's own first, as the grid's do")
    func siriFilesEveryClassroomInsert() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let siris = CDSupplyTransaction(context: context)
        // A grid mark whose own save failed, and a need the tab hasn't saved.
        let leftover = CDAttendanceRecord(context: context)
        leftover.studentID = UUID().uuidString
        leftover.date = Date()
        let need = CDOrderItem(context: context)
        // Not a classroom type: never filed.
        _ = CDClassroomMembership(context: context)

        let filed = SiriHost.recordsToFile(created: [siris], in: context)
        #expect(filed.first === siris)
        #expect(filed.count == 3)
        #expect(Set(filed.map(ObjectIdentifier.init)) == Set([siris, leftover, need].map(ObjectIdentifier.init)))
    }

    // MARK: - #28

    @Test("Restock's level colors and tags are made once")
    func restockColorsAreMadeOnce() {
        for level in RestockLevel.allCases {
            let first = AssistantRestockStyle.level(level)
            let again = AssistantRestockStyle.level(level)
            #expect(first.fill == again.fill)
            #expect(first.border == again.border)
            #expect(first.text == again.text)
            #expect(first.detail == again.detail)
            #expect(first.barOn == again.barOn)
            #expect(first.barOff == again.barOff)
        }
        #expect(AssistantRestockStyle.level(.out).barsOutlined)
        #expect(!AssistantRestockStyle.level(.low).barsOutlined)
    }

    // MARK: - #30

    @Test("Siri's lookup by id gives one child, the roster's copy, when she has a row in both stores")
    func oneEntityPerID() throws {
        let stores = try Self.twoStores()
        let (context, shared) = (stores.stack.viewContext, stores.shared)
        let id = UUID()
        let own = AssistantTestSupport.student("Maya", "Stone", in: context)
        own.id = id
        let classroom = AssistantTestSupport.student("Maya", "Stone", in: context)
        classroom.id = id
        context.assign(classroom, to: shared)
        #expect(context.safeSave())

        let entities = StudentEntityQuery.entities(for: [id], in: context)
        #expect(entities.count == 1)
        #expect(entities.first?.id == id)
        #expect(entities.first?.displayName == "Maya")
    }

    // MARK: - #31

    @Test("An assistant's level change reads its staple's needs from the classroom share only")
    func needsReadFromTheShare() throws {
        let stores = try Self.twoStores()
        let (context, shared, own) = (stores.stack.viewContext, stores.shared, stores.own)
        let ana = AssistantRestockTestSupport.ana
        let details = RestockService.StapleDetails(name: "Paper Towels", place: "Sink", source: .office)
        let staple = try #require(RestockService.addStaple(details, by: ana, in: context)).object
        #expect(context.safeSave())
        #expect(staple.objectID.persistentStore === shared)
        // A need in the private store naming the same staple isn't the class's.
        let stray = CDOrderItem(context: context)
        stray.id = UUID()
        stray.title = "Paper Towels"
        stray.supplyID = staple.id?.uuidString
        stray.createdAt = Date()
        context.assign(stray, to: own)
        #expect(context.safeSave())

        #expect(RestockService.setLevel(staple, to: .low, by: ana, in: context))
        let open = RestockService.openNeeds(in: context, store: shared)
        #expect(open.count == 1)
        #expect(open.first?.supplyID == staple.id?.uuidString)
        #expect(stray.receivedAt == nil && !stray.isDeleted)
    }

    @Test("The join screen's Sample Class tells Siri no names")
    func sampleClassSkipsSiriNames() throws {
        let stack = try AssistantTestSupport.makeStack()
        let student = AssistantTestSupport.student("Zev", "Quill", in: stack.viewContext)
        #expect(!AssistantSiriVocabulary.refresh(for: [student], sampleChosen: true))
        #expect(!AssistantRestockVocabulary.refresh(for: [], sampleChosen: true))
    }
}

// MARK: - #27

extension AssistantFix1103SR {

    @Suite("Schedule tab fetches (Fix1103 SR)")
    @MainActor
    struct ScheduleFetches: AssistantScheduleFixture {
        let stack: CoreDataStack
        let monday: Date
        let morning: Date

        init() throws {
            stack = try AssistantTestSupport.makeStack()
            monday = try AssistantTestSupport.day("2026-10-26")
            morning = try #require(AppCalendar.shared.date(byAdding: .minute, value: 9 * 60 + 15, to: monday))
        }

        @Test("The Schedule tab fetches only the blocks that can be on the day, and shows the same ones")
        func onlyTheDaysBlocks() throws {
            let lanes = makeLanes()
            let tuesday = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: monday))
            block(lanes.ourClass, 8 * 60 + 30, 60, "Monday block")
            block(lanes.ourClass, 8 * 60 + 30, 60, "Tuesday block", weekday: .tuesday)
            block(lanes.ourClass, 13 * 60, 60, "Assembly", weekday: .wednesday).onDay = monday
            block(lanes.ourClass, 14 * 60, 60, "Trip").onDay = tuesday
            #expect(context.safeSave())

            // A context of its own, so only what the load fetches is in it.
            let fresh = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            fresh.persistentStoreCoordinator = context.persistentStoreCoordinator
            let now = morning
            let tab = AssistantScheduleModel(context: fresh, guideName: { "Danny" }, now: { now })
            tab.load()

            let fetched = Set(fresh.registeredObjects.compactMap { ($0 as? CDTimetableBlock)?.values.title })
            #expect(fetched == ["Monday block", "Assembly"])
            let shown = Set(tab.rows.map(\.title))
            #expect(shown.contains("Monday block"))
            #expect(shown.contains("Assembly"))
            #expect(!shown.contains("Tuesday block"))
            #expect(!shown.contains("Trip"))
        }
    }
}

// MARK: - #29

extension AssistantSiriTests {

    @Test("A failed save of Siri's Undo of Close Arrival puts back the copies it cleared too (Fix1103 SR)")
    func failedUndoPutsBackTheCopies() async throws {
        let day = try AssistantTestSupport.day("2031-01-06")
        defer {
            SiriAttendanceChange.forget()
            AttendanceLatePhase.setLate(false, on: day)
        }
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())
        var siri = SiriAttendance(stack: stack, role: .assistant, today: day.addingTimeInterval(9 * 3_600))
        #expect(try await AssistantSiriCommands.closeArrival(siri) == 1)
        // Another device closed arrival on her too, before the two synced.
        let copy = CDAttendanceRecord(context: context)
        copy.studentID = try #require(maya.id?.uuidString)
        copy.date = day
        copy.status = .absent
        copy.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
        copy.recordedBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        copy.modifiedAt = Date().addingTimeInterval(-60)
        #expect(context.safeSave())

        siri.save = { _ in false }
        await #expect(throws: SiriAttendanceError.self) { _ = try await siri.undoLast() }
        #expect(copy.status == .absent)
        #expect(copy.absenceReasonRaw == AttendanceDeduplication.automaticAbsenceRaw)
        // Nothing of attendance is left for the next save to send: the
        // records as a save would see them, after Core Data's own bookkeeping.
        context.processPendingChanges()
        let unsaved = context.insertedObjects.union(context.updatedObjects).union(context.deletedObjects)
        #expect(!unsaved.contains { $0 is CDAttendanceRecord })
        let siris = try context.fetch(CDFetchRequest(CDAttendanceRecord.self)).filter { $0 !== copy }
        #expect(siris.count == 1)
        #expect(siris.allSatisfy { $0.status == .absent && AttendanceDeduplication.isAutomaticAbsence($0) })
        // Still remembered, so asking again tries again.
        #expect(SiriAttendanceChange.last() != nil)
    }
}
