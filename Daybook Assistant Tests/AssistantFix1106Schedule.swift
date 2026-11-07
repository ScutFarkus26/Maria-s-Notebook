import Foundation
import CoreData
import SwiftUI
import UIKit
import Testing
@testable import Daybook_Assistant

// The 2026-11-06 hunt's Schedule tab and waste fixes (Phase 3): the tab
// following the day (#14, #18), the guide's lessons on a day he's out (#15),
// the Restock menu header (#19) and the wallpaper preload (#20). #17 (the
// stepper at accessibility sizes) is checked with a screenshot.
@Suite("Assistant Schedule and waste fixes 2026-11-06")
@MainActor
struct AssistantFix1106Schedule: AssistantScheduleFixture {

    let stack: CoreDataStack
    let monday: Date
    let morning: Date

    init() throws {
        stack = try AssistantTestSupport.makeStack()
        monday = try AssistantTestSupport.day("2026-10-26")
        morning = try #require(AppCalendar.shared.date(byAdding: .minute, value: 9 * 60 + 15, to: monday))
    }

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
        let start = try AssistantTestSupport.day(day)
        return try #require(AppCalendar.shared.date(
            byAdding: .second, value: (hour * 60 + minute) * 60 + second, to: start
        ))
    }

    private func clockModel(_ clock: ScheduleClock) -> AssistantScheduleModel {
        AssistantScheduleModel(context: context, guideName: { "Danny" }, now: { clock.now })
    }

    // MARK: - #14: after a night away, today

    @Test("Shown again after a night away the tab is on today, whatever day was left; within the day, the day she left")
    func nightAwayGoesToToday() throws {
        let clock = ScheduleClock(now: morning)
        let tab = clockModel(clock)
        tab.reloadAfterAway()  // The tab first shows: Monday.
        #expect(tab.day == monday)

        // She steps back to Friday; back on the tab later the same day, Friday stays.
        tab.step(forward: false)
        let friday = try AssistantTestSupport.day("2026-10-23")
        #expect(tab.day == friday)
        clock.now = try at("2026-10-26", 15)
        tab.reloadAfterAway()
        #expect(tab.day == friday, "a day she stepped to within the day is kept")

        // The next morning (left on Restock overnight): today.
        clock.now = try at("2026-10-27", 7, 30)
        tab.reloadAfterAway()
        #expect(tab.day == (try AssistantTestSupport.day("2026-10-27")))
        #expect(tab.isToday)
    }

    // MARK: - #18: past midnight with the tab open

    @Test("Past midnight with the tab open on today, it moves to the new today; a day stepped to stays")
    func midnightMovesTodayOn() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 0, 24 * 60 - 1, "All day", weekday: .tuesday)
        #expect(context.safeSave())
        let clock = ScheduleClock(now: try at("2026-10-26", 23, 59))
        let tab = clockModel(clock)
        tab.reloadAfterAway()
        #expect(tab.isToday)

        clock.now = try at("2026-10-27", 0, 0, 1)
        tab.minuteTurned()
        let tuesday = try AssistantTestSupport.day("2026-10-27")
        #expect(tab.day == tuesday, "the stepper said Today beside yesterday's date")
        #expect(tab.isToday)
        #expect(tab.clock == clock.now)
        #expect(tab.nowCard(at: tab.clock) != nil, "the Now card went blank")

        // On another day at midnight, that day stays: Thursday, at Wednesday's midnight.
        tab.step(forward: true)
        tab.step(forward: true)
        let stepped = tab.day
        #expect(stepped == (try AssistantTestSupport.day("2026-10-29")))
        clock.now = try at("2026-10-28", 0, 0, 1)
        tab.minuteTurned()
        #expect(tab.day == stepped)
    }

    // MARK: - #15: the guide's lessons on a day he's out

    @Test("On a day the guide is out, his booked lessons aren't shown; on another day they are")
    func guideOutHidesHisLessons() throws {
        let lanes = makeLanes()
        block(lanes.ourClass, 8 * 60 + 30, 7 * 60, "School day")
        let maya = student("Maya", "Stone", .upper)
        let ari = student("Ari", "Klein", .upper)
        booking([maya])  // The morning's list.
        booking([ari], minute: 10 * 60)  // At 10:00.
        #expect(context.safeSave())

        let tab = model()
        tab.laneFilter = nil
        #expect(tab.rows.filter { $0.title == "With Danny" }.count == 2, "shown while he's in")

        let out = CDTimetableChange(context: context)
        out.day = monday
        out.kind = .out
        out.laneID = lanes.guide.id?.uuidString
        #expect(context.safeSave())
        tab.load()
        #expect(tab.outLines == ["Danny is out."])
        for lane in [nil, lanes.guide.id] {
            tab.laneFilter = lane
            #expect(!tab.rows.contains { $0.title == "With Danny" }, "with lane \(String(describing: lane))")
        }
        tab.laneFilter = nil
        #expect(tab.rows.contains { $0.title == "School day" }, "the rest of the day still shows")
    }

    // MARK: - #19: the Restock menu header

    @Test("A Restock tile's redraws don't work out its menu header")
    func restockHeaderNotWorkedOutOnRedraw() throws {
        let state = RestockTileState()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let host = UIHostingController(rootView: RestockTileHost(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        for count in 1...5 {
            state.markedBy = "You · 8:1\(count) AM"
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(state.redraws > 1, "the tile redrew")
        #expect(state.headerCalls == 0, "the header was worked out on \(state.headerCalls) redraws")
    }

    // MARK: - #20: the wallpaper preload

    @Test("While the photo is read ahead, the grid's own read waits for it rather than decoding it again")
    func loadWaitsForThePreload() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WallpaperFix1106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.smallJPEG().write(to: directory.appending(path: "photo.jpg"))
        let photo = AssistantWallpaperPhoto(directory: directory)

        let preload = Task { await photo.preload(chosen: AssistantWallpaper.photo.rawValue) }
        for _ in 0..<1_000 where !photo.isPreloading { await Task.yield() }
        #expect(photo.isPreloading)
        photo.loadIfNeeded()
        #expect(photo.image == nil, "the grid decoded it on the main thread")
        await preload.value
        #expect(photo.image != nil, "the preload's photo is shown")
        #expect(!photo.isPreloading)
    }

    @Test("A let-go while the photo is read ahead still gives the grid that asked the photo")
    func letGoDuringPreloadStillLoads() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WallpaperFix1106-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.smallJPEG().write(to: directory.appending(path: "photo.jpg"))
        let photo = AssistantWallpaperPhoto(directory: directory)

        let preload = Task { await photo.preload(chosen: AssistantWallpaper.photo.rawValue) }
        for _ in 0..<1_000 where !photo.isPreloading { await Task.yield() }
        photo.loadIfNeeded()
        photo.release(unlessChosen: AssistantWallpaper.sky.rawValue)
        await preload.value
        #expect(photo.image != nil, "the grid asked, so the photo is read after all")
    }

    private static func smallJPEG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }
}

@MainActor
private final class ScheduleClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
@Observable
private final class RestockTileState {
    var markedBy = "You · 8:10 AM"
    @ObservationIgnored var headerCalls = 0
    @ObservationIgnored var redraws = 0
}

/// One tile whose "who set it" line changes, so it redraws.
private struct RestockTileHost: View {
    let state: RestockTileState

    var body: some View {
        tile()
    }

    private func tile() -> some View {
        state.redraws += 1
        return AssistantRestockTile(
            name: "Paper towels", level: .low, markedBy: state.markedBy, hasNote: false,
            menuHeader: {
                state.headerCalls += 1
                return "Set by you at 8:10 AM"
            },
            onTap: { true }, onSetLevel: { _ in }, onNote: {}, onHistory: {}
        )
    }
}
