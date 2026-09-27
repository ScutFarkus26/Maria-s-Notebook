import CoreData
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Today's view model is made once per screen, not once per redraw of the
/// screen's parent.
///
/// `RootDetailContent` builds the Today screen afresh on every pass of its
/// body. The screen used to be `TodayView(context:)`, whose initializer made a
/// `TodayViewModel` each time — three notification observers registered and
/// removed, a cache manager, the day's cleanup gate — that `@State` then threw
/// away in favour of the first. `TodayRootView` makes nothing until the screen
/// appears.
@Suite("Today root view")
@MainActor
struct TodayRootViewTests {

    /// `TodayView`'s old initializer, verbatim, on a view that shows nothing.
    private struct OldTodayViewInit: View {
        @State var viewModel: TodayViewModel

        init(context: NSManagedObjectContext) {
            viewModel = TodayViewModel(context: context, calendar: AppCalendar.shared)
        }

        var body: some View { EmptyView() }
    }

    @Test("A hundred passes of the root detail's Today branch make no view model")
    func rootPassesMakeNone() throws {
        let context = try CoreDataTestHelpers.makeContext()

        // What each pass cost before: one model per initializer call.
        let beforeOld = TodayViewModel.madeCount
        for _ in 0..<100 {
            _ = OldTodayViewInit(context: context)
        }
        #expect(TodayViewModel.madeCount - beforeOld == 100)

        let before = TodayViewModel.madeCount
        for _ in 0..<100 {
            _ = RootDetailContent(selectedNavItem: .today).body
            _ = TodayRootView()
        }
        #expect(TodayViewModel.madeCount == before)
    }
}
