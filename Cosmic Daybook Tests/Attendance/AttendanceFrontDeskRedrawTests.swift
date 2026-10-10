import Foundation
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CosmicDaybook

/// The roll band's buttons and the front-desk control redraw only at the
/// moments they change (the due window opening, and the due time), and wait
/// for nothing once those have passed. An explicit TimelineView did this
/// until 2026-10-10, but once all its moments had passed (every day after the
/// due time, and every past day) it redrew them every frame, as it did the
/// Daybook Assistant's bar (`AssistantFrontDeskRowTests`).
@Suite("Front-desk redraws")
@MainActor
struct AttendanceFrontDeskRedrawTests {

    private func day(_ iso: String) throws -> Date {
        try CoreDataTestHelpers.day(iso)
    }

    private func urgency(on day: Date, at now: Date, deadlineMinutes: Int = 540) -> AttendanceEmailLog.Urgency {
        AttendanceEmailLog.urgency(for: day, deadlineMinutes: deadlineMinutes, now: now)
    }

    // MARK: - The moments

    @Test("The moments are the due window opening and the due time, where the line changes")
    func momentsAreWhereTheLineChanges() throws {
        let monday = try day("2026-10-12")
        func at(_ hour: Int, _ minute: Int) -> Date {
            monday.addingTimeInterval(Double(hour * 3_600 + minute * 60))
        }
        let times = AttendanceEmailLog.changeTimes(on: monday, deadlineMinutes: 540)
        #expect(times == [at(8, 30), at(9, 0)])
        #expect(urgency(on: monday, at: at(8, 30).addingTimeInterval(-1)) == .none)
        #expect(urgency(on: monday, at: at(8, 30)) == .due(at(9, 0)))
        #expect(urgency(on: monday, at: at(9, 0).addingTimeInterval(-1)) == .due(at(9, 0)))
        #expect(urgency(on: monday, at: at(9, 0)) == .overdue(at(9, 0)))

        // The guide's own due time moves both, and any time of the day works.
        #expect(AttendanceEmailLog.changeTimes(on: at(14, 0), deadlineMinutes: 525) == [at(8, 15), at(8, 45)])
    }

    @Test("Before the due window, it waits for both moments")
    func beforeTheWindow() throws {
        let monday = try day("2026-10-12")
        let times = AttendanceEmailLog.changeTimes(on: monday, deadlineMinutes: 540)
        let now = monday.addingTimeInterval(7 * 3_600)
        #expect(RedrawsAt<EmptyView>.timesAhead(times, now: now) == times)
    }

    @Test("Inside the due window, it waits only for the due time")
    func insideTheWindow() throws {
        let monday = try day("2026-10-12")
        let times = AttendanceEmailLog.changeTimes(on: monday, deadlineMinutes: 540)
        let now = times[0].addingTimeInterval(60)
        #expect(RedrawsAt<EmptyView>.timesAhead(times, now: now) == [times[1]])
    }

    @Test("At and after the due time, and on a past day, it waits for nothing")
    func afterTheDueTime() throws {
        let monday = try day("2026-10-12")
        let times = AttendanceEmailLog.changeTimes(on: monday, deadlineMinutes: 540)
        #expect(RedrawsAt<EmptyView>.timesAhead(times, now: times[1]).isEmpty)
        #expect(RedrawsAt<EmptyView>.timesAhead(times, now: times[1].addingTimeInterval(3_600)).isEmpty)
        #expect(RedrawsAt<EmptyView>.timesAhead(times, now: try day("2026-10-13")).isEmpty)
    }

    #if os(iOS)

    // MARK: - On screen

    /// When the probe's content was drawn.
    private final class Draws {
        private(set) var times: [Date] = []

        /// Notes a draw; returns how many there have been.
        func record() -> Int {
            times.append(Date())
            return times.count
        }
    }

    /// Puts `view` on screen in a window of its own; hide the window to finish.
    private func show(_ view: some View) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    /// Polls until `draws` holds at least `count` draws, for up to ten seconds.
    private func wait(for count: Int, in draws: Draws) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while draws.times.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A moment still ahead redraws the content when it comes")
    func redrawsAtAMomentAhead() async throws {
        let draws = Draws()
        let moment = Date().addingTimeInterval(1)
        let window = try show(RedrawsAt(times: [moment]) { Text(verbatim: "Drawn \(draws.record())") })
        defer { window.isHidden = true }
        try await wait(for: 1, in: draws)
        let before = draws.times.count
        #expect(try #require(draws.times.first) < moment)

        try await wait(for: before + 1, in: draws)
        let redraw = try #require(draws.times.last)
        #expect(draws.times.count > before)
        #expect(redraw >= moment)
    }

    @Test("Once every moment has passed, the content is drawn and then left alone")
    func stillOnceTheMomentsHavePassed() async throws {
        let draws = Draws()
        let passed = [Date().addingTimeInterval(-3_600), Date().addingTimeInterval(-60)]
        let window = try show(RedrawsAt(times: passed) { Text(verbatim: "Drawn \(draws.record())") })
        defer { window.isHidden = true }
        try await wait(for: 1, in: draws)
        let settled = draws.times.count

        // Every frame for a second would be 60 draws or more.
        try await Task.sleep(for: .seconds(1))
        #expect(draws.times.count - settled < 5)
    }

    #endif
}
