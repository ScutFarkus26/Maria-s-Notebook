import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The guide shares this school year only, and takes last year's children and marks out of
// the share when a new year begins. On the phone that means the grid pages no earlier than
// the share's first day with attendance, and a child whose row was just deleted by an
// import is never marked.
@Suite("Assistant and this year's share")
@MainActor
struct AssistantShareScopeTests {

    private func mark(_ student: CDStudent, on day: Date, in context: NSManagedObjectContext) {
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.id?.uuidString ?? ""
        record.date = day
        record.status = .present
    }

    @Test("Paging back stops at the share's first day with attendance")
    func pagingStopsAtFirstDay() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let monday = try AssistantTestSupport.day("2031-03-10")
        let tuesday = try AssistantTestSupport.day("2031-03-11")
        let maya = AssistantTestSupport.student("Maya", "Cedar", in: context)
        mark(maya, on: monday, in: context)
        mark(maya, on: tuesday, in: context)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack, on: tuesday)
        #expect(model.earliestDay == monday)
        #expect(model.canStepBack)
        model.step(forward: false)
        #expect(model.date == monday)
        #expect(!model.canStepBack)
        model.step(forward: false)
        #expect(model.date == monday) // nothing of this school year before it
        model.step(forward: true)
        #expect(model.date == tuesday)
    }

    @Test("With no attendance yet, paging back is not limited")
    func noFloorWithoutAttendance() throws {
        let stack = try AssistantTestSupport.makeStack()
        _ = AssistantTestSupport.student("Maya", "Cedar", in: stack.viewContext)
        #expect(stack.viewContext.safeSave())
        let tuesday = try AssistantTestSupport.day("2031-03-11")
        let model = AssistantTestSupport.viewModel(stack, on: tuesday)
        #expect(model.earliestDay == nil)
        model.step(forward: false)
        #expect(model.date == (try AssistantTestSupport.day("2031-03-10")))
    }

    @Test("A child deleted by an import is never marked; the day reloads without her")
    func goneChildNotMarked() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let tuesday = try AssistantTestSupport.day("2031-03-11")
        AssistantTestSupport.student("Ari", "Oak", in: context)
        let leora = AssistantTestSupport.student("Leora", "Birch", in: context)
        #expect(context.safeSave())
        let model = AssistantTestSupport.viewModel(stack, on: tuesday)
        let leoraRow = try #require(model.rows.first { $0.student == leora })

        context.delete(leora)
        #expect(context.safeSave())
        #expect(leoraRow.studentIsGone)

        model.tap(leoraRow)
        model.markAbsent(reason: .none, for: leoraRow)
        model.setNote("Left early", for: leoraRow)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
        #expect(model.rows.map(\.student.firstName) == ["Ari"])
    }
}
