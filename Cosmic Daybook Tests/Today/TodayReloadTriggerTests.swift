import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What Today's reload triggers include beyond work and presentations: an
/// attendance mark (the lesson rows' "3 of 4 here" and absent chips, on
/// iPhone too, where the attendance band is hidden) and the meetings (one
/// finished in the Mac's meeting window, or booked elsewhere).
@Suite("Today reload triggers")
@MainActor
struct TodayReloadTriggerTests {

    @Test("An attendance mark or a meeting saved on another context reloads Today")
    func attendanceAndMeetingsReload() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let meeting = CDScheduledMeeting(context: context)
        meeting.studentID = UUID().uuidString
        meeting.date = AppCalendar.startOfDay(Date())
        #expect(CoreDataTestHelpers.save(context))
        let meetingID = meeting.objectID
        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        let afterFirst = viewModel.reloadCount

        // The Assistant's mark, arriving as the import context's save.
        let importContext = stack.newBackgroundContext()
        importContext.performAndWait {
            let record = CDAttendanceRecord(context: importContext)
            record.studentID = UUID().uuidString
            record.date = Date()
            _ = importContext.safeSave()
        }
        viewModel.scheduleReloadIfInputsChanged()
        await viewModel.reloadTask?.value
        #expect(viewModel.reloadCount == afterFirst + 1)

        // A meeting finished in its own window deletes the scheduled one.
        importContext.performAndWait {
            importContext.delete(importContext.object(with: meetingID))
            _ = importContext.safeSave()
        }
        viewModel.scheduleReloadIfInputsChanged()
        await viewModel.reloadTask?.value
        #expect(viewModel.reloadCount == afterFirst + 2)
    }
}
