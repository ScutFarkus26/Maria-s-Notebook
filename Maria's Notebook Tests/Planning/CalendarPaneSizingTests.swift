import CoreGraphics
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The Scheduled calendar's share of the workspace is a setting the guide sets
/// by dragging, so it has to be bounded and it has to survive relaunching.
@Suite("Calendar pane sizing")
@MainActor
struct CalendarPaneSizingTests {

    @Test("Neither half can be squeezed away")
    func fractionIsClamped() {
        #expect(WorksAgendaView.clampFraction(0.42) == 0.42)
        // A drag that runs off the top or bottom of the screen stops at the bound.
        #expect(WorksAgendaView.clampFraction(0.95) == WorksAgendaView.maxCalendarFraction)
        #expect(WorksAgendaView.clampFraction(0.01) == WorksAgendaView.minCalendarFraction)
        // Nonsense from a corrupted or hand-edited setting still resolves.
        #expect(WorksAgendaView.clampFraction(-3) == WorksAgendaView.minCalendarFraction)
    }

    @Test("The share is applied to the space available")
    func heightFollowsFraction() {
        #expect(WorksAgendaView.calendarHeight(fraction: 0.5, in: 1000) == 500)
        #expect(WorksAgendaView.calendarHeight(fraction: 0.25, in: 1000) == 250)
    }

    @Test("A short window keeps the calendar deep enough to drop onto")
    func pointsFloorWinsOnSmallScreens() {
        // 20% of a short iPhone workspace would be unusable as a drop target.
        let height = WorksAgendaView.calendarHeight(fraction: 0.2, in: 400)
        #expect(height == WorksAgendaView.minCalendarHeight)
        #expect(height > 400 * WorksAgendaView.minCalendarFraction)
    }

    @Test("The stored default sits inside the bounds")
    func defaultIsValid() {
        // The @AppStorage default must not be a value the clamp would move,
        // or a fresh install would appear to have been resized already.
        let storedDefault = 0.42
        #expect(WorksAgendaView.clampFraction(storedDefault) == storedDefault)
    }
}
