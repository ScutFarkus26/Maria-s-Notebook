import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, Part 2 #88: cancelled going-outs could not be seen
/// anywhere. (#90's resource delete went with Resources on 2026-11-22.)
@Suite("Going Out (fix 10-10 J1)")
@MainActor
struct SmallerFeaturesFix1010J1Tests {

    @Test("Cancelled going-outs get a list of their own")
    func cancelledGoingOutsListed() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for (title, status) in [
            ("Library", GoingOutStatus.planning),
            ("Bakery", .completed),
            ("Zoo", .cancelled)
        ] {
            let goingOut = CDGoingOut(context: context)
            goingOut.title = title
            goingOut.status = status
        }
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = GoingOutViewModel()
        viewModel.loadData(context: context)

        #expect(viewModel.activeGoingOuts.map(\.title) == ["Library"])
        #expect(viewModel.completedGoingOuts.map(\.title) == ["Bakery"])
        #expect(viewModel.cancelledGoingOuts.map(\.title) == ["Zoo"])
    }
}
