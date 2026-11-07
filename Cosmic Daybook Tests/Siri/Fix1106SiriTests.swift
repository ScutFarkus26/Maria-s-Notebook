import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

// The 2026-11-06 Daybook Assistant bug hunt, the notebook's half of the
// shared Siri and ParentLocker code (report "Daybook Assistant bug hunt
// 2026-11-06", #4, #6, #13). The Assistant's half is in its own target
// (`AssistantFix1106Siri`).

/// Siri in the notebook: a View-only device says so (#6), and the guide's
/// child lookup still reads both stores (#13). Serialized: View only and
/// Siri's undo memory are app-wide.
@Suite("Siri fixes 2026-11-06", .serialized)
@MainActor
struct Fix1106SiriTests {

    private let monday: Date

    init() throws {
        monday = try CoreDataTestHelpers.day("2026-10-12")
        SiriAttendanceChange.forget()
    }

    private static func student(_ first: String, in context: NSManagedObjectContext) -> CDStudent {
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = first
        student.lastName = "Stone"
        student.enrollmentStatusRaw = CDStudent.EnrollmentStatus.enrolled.rawValue
        return student
    }

    // MARK: - #6 View only

    @Test("A notebook joined as a View-only assistant: Siri's here says the View-only message, and marks nothing (#6)")
    func viewOnlySaysSo() async throws {
        let was = ClassroomPermissions.shareIsViewOnly
        defer { ClassroomPermissions.shareIsViewOnly = was }
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let maya = Self.student("Maya", in: stack.viewContext)
        #expect(stack.viewContext.safeSave())
        ClassroomPermissions.shareIsViewOnly = true

        let siri = SiriAttendance(stack: stack, role: .assistant, today: monday.addingTimeInterval(9 * 3_600))
        let error = await #expect(throws: SiriAttendanceError.self) { try await siri.markHere(maya) }
        let said = error.map { String(localized: $0.localizedStringResource) }
        #expect(said == SiriHost.viewOnlyMessage)
        #expect(said?.contains("Open the app") == false)
        #expect(stack.viewContext.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
        #expect(SiriAttendanceChange.last() == nil)
    }

    // MARK: - #13 The guide's lookup reads both stores

    @Test("The guide's Siri still finds a child who lives in the private store, beside a classroom share (#13)")
    func guideFindsPrivateStoreChild() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let coordinator = try #require(context.persistentStoreCoordinator)
        let own = try #require(coordinator.persistentStores.first)
        let shared = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.sharedConfiguration,
            at: URL(fileURLWithPath: "/dev/null/shared-\(UUID().uuidString)")
        )
        #expect(own !== shared)
        let maya = Self.student("Maya", in: context)
        context.assign(maya, to: own)
        #expect(context.safeSave())

        let siri = SiriAttendance(stack: stack, role: .leadGuide, today: monday.addingTimeInterval(9 * 3_600))
        let entity = try #require(StudentEntity(student: maya))
        let found = try siri.student(for: entity)
        #expect(found.objectID == maya.objectID)
        #expect(found.objectID.persistentStore === own)
    }
}

/// #4: whether a class of Close Arrival & Send has already gone is kept with
/// what's owed, so after a relaunch Siri's Undo still warns that some
/// absences may be in ParentLocker. It was kept in memory only.
@Suite("ParentLocker fixes 2026-11-06: kept across a relaunch")
@MainActor
struct Fix1106ParentLockerOwedTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    @Test("A half-sent Close Arrival & Send still reads as partly sent after a relaunch (#4)")
    func batchSentSurvivesRelaunch() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let device = Fix1105ADevice(site: site, clock: clock, unsent: unsent, marks: Marks.closed)
        // One class saves, the other can't load: it has gone, in part, and waits to retry.
        device.wire.rosterFailures[5102] = [.unreachable]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(!device.sync.closeArrivalSendUnsent)
        #expect(unsent.load()?.batchSent == true)

        // iOS ends the app; the next launch picks up what's owed.
        device.sync.stop()
        let relaunched = Fix1105ADevice(site: site, clock: clock, unsent: unsent, marks: Marks.closed)
        #expect(relaunched.sync.closeArrivalBatchSent)
        #expect(relaunched.sync.closeArrivalPending)
        #expect(!relaunched.sync.closeArrivalSendUnsent, "a class of it has gone")
        #expect(SiriAttendance.closeArrivalPartlySent(state: .retrying, unsent: relaunched.sync.closeArrivalSendUnsent))
    }

    @Test("What's owed saved before the fix reads as nothing gone; the new field round-trips (#4)")
    func batchSentDecodes() throws {
        let old = Data(#"{"day":"2026-10-12","children":[],"wholeClass":true,"arrivalClosed":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ParentLockerUnsent.self, from: old)
        #expect(!decoded.batchSent)
        let saved = ParentLockerUnsent(day: "2026-10-12", children: [], wholeClass: true, batchSent: true)
        let again = try JSONDecoder().decode(ParentLockerUnsent.self, from: JSONEncoder().encode(saved))
        #expect(again.batchSent)
        #expect(again == saved)
    }
}
