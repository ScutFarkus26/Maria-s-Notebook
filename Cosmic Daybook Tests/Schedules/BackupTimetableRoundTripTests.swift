import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Backup v42 carries Schedules: the lanes, weekly and one-off blocks with
/// their days and children, one day's changes, and the bookings. Restore
/// matches rows on `id`, as every model-driven row does.
@Suite("Backup: Schedules", .serialized)
@MainActor
struct BackupTimetableRoundTripTests {

    private typealias Support = TimetableTestSupport
    private let now = Support.time(TimetableTestSupport.monday, 8)

    /// A notebook with the lanes, a weekly block with its days and children,
    /// a turn, a one-off, a day's change, a person out, and a booking.
    private func seed(_ source: NSManagedObjectContext) throws -> (CDTimetableBlock, CDTimetableBooking) {
        let lanes = TimetableService.makeStarterLanes(in: source, now: now)
        let devora = TimetableService.addPerson(named: "Morah Devora", in: source, now: now)
        var group = TimetableBlockValues(
            startMinute: Support.minutes(9), lengthMinutes: 45, title: "Chumash", note: "Bring siddurim",
            studentIDs: [Support.lucy, Support.ari]
        )
        let weekly = try #require(TimetableService.addBlock(
            group, to: devora, on: [.monday], from: Support.lastMonday, in: source, now: now
        ).first)
        weekly.validUntil = Support.day(2026, 12, 31)
        var turn = TimetableBlockValues(startMinute: Support.minutes(10, 30), lengthMinutes: 75, title: "Navi")
        turn.teacherLaneID = devora.id
        TimetableService.addBlock(turn, to: lanes[1], on: [.monday], in: source, now: now)
        TimetableService.addOneOff(
            TimetableBlockValues(startMinute: Support.minutes(14), title: "Early dismissal"), to: lanes[0],
            on: Support.tuesday, in: source, now: now
        )
        group.startMinute = Support.minutes(9, 15)
        TimetableService.setDayValues(group, for: weekly, on: Support.monday, in: source, now: now)
        TimetableService.setOut(devora, true, on: Support.tuesday, in: source, now: now)
        let booking = CDTimetableBooking(context: source)
        booking.presentationID = UUID().uuidString
        booking.day = Support.monday
        booking.half = .afternoon
        booking.setMinute = Support.minutes(13, 30)
        booking.order = 2
        booking.studentIDs = [Support.bea]
        booking.sourceModifiedAt = now
        return (weekly, booking)
    }

    @Test("v42: lanes, blocks, changes and bookings survive a Replace restore, and read the same day")
    func roundTrip() async throws {
        let source = try Support.context()
        let (weekly, booking) = try seed(source)
        #expect(CoreDataTestHelpers.save(source))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: source, to: url)
        let restored = try Support.context()
        try await BackupTestUtil.importCurrentBackup(from: url, into: restored, mode: .replace)

        for entity in ["TimetableLane", "TimetableBlock", "TimetableChange", "TimetableBooking"] {
            #expect(
                try BackupTestUtil.count(entityName: entity, in: restored)
                    == BackupTestUtil.count(entityName: entity, in: source),
                "\(entity)"
            )
        }
        let back = try #require(try BackupTestUtil.fetchByID(
            CDTimetableBlock.self, weekly.id, entityName: "TimetableBlock", in: restored
        ))
        #expect(back.values == weekly.values)
        #expect(back.weekday == .monday)
        #expect(back.validFrom == Support.lastMonday)
        #expect(back.validUntil == Support.day(2026, 12, 31))
        #expect(back.studentIDs == [Support.lucy, Support.ari])
        let backBooking = try #require(try BackupTestUtil.fetchByID(
            CDTimetableBooking.self, booking.id, entityName: "TimetableBooking", in: restored
        ))
        #expect(backBooking.presentationID == booking.presentationID)
        #expect(backBooking.half == .afternoon)
        #expect(backBooking.setMinute == Support.minutes(13, 30))
        #expect(backBooking.order == 2)
        #expect(backBooking.studentIDs == [Support.bea])
        #expect(backBooking.sourceModifiedAt == now)

        // Both days read the same from the restored notebook.
        for day in [Support.monday, Support.tuesday] {
            #expect(Support.resolveStored(day, in: restored) == Support.resolveStored(day, in: source))
        }
        #expect(Support.resolveStored(Support.tuesday, in: restored).changeCount == 2)
    }

    @Test("Schedules entries are written under shared/, as the classroom share holds them")
    func sharedPrefix() {
        for entity in ["TimetableLane", "TimetableBlock", "TimetableChange", "TimetableBooking"] {
            #expect(CoreDataStack.sharedEntityNames.contains(entity))
        }
        // v42 brought them; later formats still carry them.
        #expect(BackupWriter.formatVersion >= 42)
        #expect(BackupReader.supportedFormatVersions.contains(42))
        #expect(BackupReader.supportedFormatVersions.contains(41))
    }
}
