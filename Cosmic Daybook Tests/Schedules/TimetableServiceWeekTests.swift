import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `TimetableService` over a whole week: copying a day, replacing a lane's
/// week (MCP's set_timetable), and where new rows land with two stores.
@Suite("Schedules: the timetable service, whole weeks", .serialized)
@MainActor
struct TimetableServiceWeekTests {

    private typealias Support = TimetableTestSupport
    private let now = Support.time(TimetableTestSupport.monday, 8)

    private func values(_ hour: Int, _ minute: Int = 0, _ length: Int = 60, _ title: String) -> TimetableBlockValues {
        TimetableBlockValues(startMinute: Support.minutes(hour, minute), lengthMinutes: length, title: title)
    }

    private func titles(_ lane: String, _ day: Date, _ context: NSManagedObjectContext) -> [String] {
        Support.storedTitles(lane, on: day, in: context)
    }

    @Test("Copy a day to other weekdays, without doubling a block already there")
    func copyDay() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Our class", kind: .room, in: context, now: now)
        TimetableService.addBlock(values(8, 30, 90, "Work cycle"), to: lane, on: [.monday], in: context, now: now)
        TimetableService.addBlock(
            values(12, 0, 30, "Lunch"), to: lane, on: [.monday, .wednesday], in: context, now: now
        )
        let copies = TimetableService.copyDay(
            .monday, of: lane, to: [.tuesday, .wednesday, .monday], in: context, now: now
        )
        #expect(copies.count == 3, "Tuesday gets both, Wednesday only what it lacked")
        #expect(context.safeSave())
        #expect(titles("Our class", Support.tuesday, context) == ["Work cycle", "Lunch"])
        #expect(titles("Our class", Support.wednesday, context) == ["Work cycle", "Lunch"])
    }

    @Test("Replacing a week from a day on keeps the weeks before it and the one-offs")
    func replaceWeek() throws {
        let context = try Support.context()
        let lane = TimetableService.addLane(named: "Morah Devora", kind: .person, in: context, now: now)
        TimetableService.addBlock(values(9, 0, 45, "Chumash"), to: lane, on: [.monday], in: context, now: now)
        TimetableService.addOneOff(values(14, 0, 30, "Trip"), to: lane, on: Support.nextMonday, in: context, now: now)
        let week = [
            TimetableService.WeeklyBlock(weekday: .monday, values: values(9, 30, 45, "Navi")),
            TimetableService.WeeklyBlock(weekday: .friday, values: values(9, 0, 30, "Parsha"))
        ]
        let added = TimetableService.replaceWeek(of: lane, with: week, from: Support.monday, in: context, now: now)
        #expect(added.count == 2)
        #expect(context.safeSave())
        #expect(titles("Morah Devora", Support.lastMonday, context) == ["Chumash"])
        #expect(titles("Morah Devora", Support.monday, context) == ["Navi"])
        #expect(titles("Morah Devora", Support.nextMonday, context) == ["Navi", "Trip"])
        #expect(titles("Morah Devora", Support.friday, context) == ["Parsha"])
    }

    @Test("With two stores, new rows go into the private store, from which the share takes them")
    func rowsGoToThePrivateStore() throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("timetable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration,
                at: directory.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let privateStore = try #require(coordinator.persistentStores.first {
            $0.configurationName == CoreDataStack.privateConfiguration
        })

        let lanes = TimetableService.makeStarterLanes(in: context, now: now)
        let block = try #require(TimetableService.addBlock(
            values(9, 0, 60, "Math"), to: lanes[0], on: [.monday], in: context, now: now
        ).first)
        TimetableService.cancel(block, on: Support.monday, in: context, now: now)
        #expect(context.safeSave())
        let rows: [NSManagedObject] = lanes + [block]
            + TimetableService.changes(from: Support.monday, through: Support.monday, in: context)
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0.objectID.persistentStore === privateStore })
    }
}
