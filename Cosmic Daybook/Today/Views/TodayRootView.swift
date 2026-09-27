// TodayRootView.swift
// Owns Today's view model for as long as the screen is up.

import CoreData
import SwiftUI

/// The Today screen as the root detail shows it: makes one `TodayViewModel`
/// when the screen first appears and hands it to `TodayView`.
///
/// `TodayView` used to make its model in `init(context:)`, and
/// `RootDetailContent` builds the screen again on every redraw of its own.
/// SwiftUI kept the first model in `@State` and dropped every later one, but
/// each had already been built: three change-flag observers registered and
/// removed, a cache manager, the day's cleanup gate asked. This is Apple's
/// pattern for an `@Observable` model that needs what only the view has (here
/// the environment's context): optional state, filled when the view appears.
/// Re-making this view makes nothing.
struct TodayRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: TodayViewModel?

    var body: some View {
        if let viewModel {
            TodayView(viewModel: viewModel)
        } else {
            // `onAppear` rather than `.task`, like the other screens that make
            // their model on appearance (`StudentNotesTimelineView`,
            // `PresentationDetailView`): it runs as the placeholder goes in,
            // not after a task hop, so Today replaces it without a blank frame
            // to show.
            Color.clear
                .onAppear {
                    guard viewModel == nil else { return }
                    viewModel = TodayViewModel(context: viewContext, calendar: AppCalendar.shared)
                }
        }
    }
}
