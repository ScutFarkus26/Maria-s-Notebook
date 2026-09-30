import Foundation
import Testing
@testable import CosmicDaybook

// An attendance screen left open overnight must not take the morning's marks
// onto yesterday, and must not yank the guide off a day she chose.
@Suite("Attendance day rollover")
struct AttendanceDayRolloverTests {
    private let monday = Date(timeIntervalSinceReferenceDate: 0)
    private var tuesday: Date { monday.addingTimeInterval(86_400) }
    private var lastFriday: Date { monday.addingTimeInterval(-3 * 86_400) }

    @Test("The first look adopts today")
    func firstLook() {
        let next = AttendanceDayRollover.advance(selected: lastFriday, anchor: nil, newAnchor: monday)
        #expect(next.selected == monday)
        #expect(next.anchor == monday)
    }

    @Test("Still on yesterday's today, the screen follows the new day")
    func followsToday() {
        let next = AttendanceDayRollover.advance(selected: monday, anchor: monday, newAnchor: tuesday)
        #expect(next.selected == tuesday)
        #expect(next.anchor == tuesday)
    }

    @Test("A day chosen on purpose stays put")
    func keepsChosenDay() {
        let next = AttendanceDayRollover.advance(selected: lastFriday, anchor: monday, newAnchor: tuesday)
        #expect(next.selected == lastFriday)
        #expect(next.anchor == tuesday)
    }

    @Test("Nothing moves when today hasn't changed")
    func sameDay() {
        let next = AttendanceDayRollover.advance(selected: lastFriday, anchor: monday, newAnchor: monday)
        #expect(next.selected == lastFriday)
        #expect(next.anchor == monday)
    }
}
