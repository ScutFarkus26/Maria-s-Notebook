import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The long-press menu: Absent with its reason in one step, and the line
// saying who made the mark.
@Suite("Assistant tile menu")
@MainActor
struct AssistantMenuTests {

    typealias Model = AssistantAttendanceViewModel

    @Test("Absent with a reason is one step, today or ahead")
    func absentWithReason() throws {
        let stack = try AssistantTestSupport.makeStack()
        AssistantTestSupport.student("Ari", "Cedar", in: stack.viewContext)
        for date in [Date(), Calendar.current.date(byAdding: .day, value: 2, to: Date())!] {
            let model = AssistantTestSupport.viewModel(stack, on: date)
            let row = try #require(model.rows.first)
            model.markAbsent(reason: .appointment, for: row)
            let marked = try #require(model.rows.first)
            #expect(marked.status == .absent)
            #expect(marked.absenceReason == .appointment)

            model.markAbsent(reason: .none, for: marked)
            #expect(try #require(model.rows.first).absenceReason == .none)
        }
    }

    private func row(
        _ status: AttendanceStatus = .present,
        by role: String?,
        id: String? = nil,
        name: String? = nil,
        at time: Date? = nil
    ) throws -> Model.Row {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let student = AssistantTestSupport.student("Ari", "Cedar", in: context)
        let record = CDAttendanceRecord(context: context)
        record.studentID = student.id!.uuidString
        record.date = Calendar.current.startOfDay(for: Date())
        record.status = status
        record.recordedBy = role
        record.recordedByID = id
        record.recordedByName = name
        record.markedAt = time
        return Model.Row(student: student, record: record, shortName: "Ari", day: Date())
    }

    @Test("Marked by: you, another assistant, the guide (by name when known)")
    func markedByLines() throws {
        let eight = Calendar.current.date(bySettingHour: 8, minute: 2, second: 0, of: Date())!
        let assistant = "assistant"
        let guide = "leadGuide"

        let mine = try row(by: assistant, id: "me", name: "Rivka", at: eight)
        #expect(Model.markedByLine(for: mine, myRecordName: "me", myName: "Rivka", guideName: nil)
            == "Marked by you at \(AssistantAttendanceTile.clock(eight))")

        let theirs = try row(by: assistant, id: "other", name: "Chana")
        #expect(Model.markedByLine(for: theirs, myRecordName: "me", myName: "Rivka", guideName: nil)
            == "Marked by Chana")

        // Without her record name, the typed name decides.
        let byName = try row(by: assistant, name: "Rivka")
        #expect(Model.markedByLine(for: byName, myRecordName: nil, myName: "Rivka", guideName: nil)
            == "Marked by you")

        let guideMark = try row(by: guide)
        #expect(Model.markedByLine(for: guideMark, myRecordName: "me", myName: "Rivka", guideName: nil)
            == "Marked by your guide")
        #expect(Model.markedByLine(for: guideMark, myRecordName: "me", myName: "Rivka", guideName: "Danny")
            == "Marked by Danny")

        let unmarked = try row(.unmarked, by: assistant, id: "me")
        #expect(Model.markedByLine(for: unmarked, myRecordName: "me", myName: nil, guideName: nil) == nil)
        let unattributed = try row(by: nil)
        #expect(Model.markedByLine(for: unattributed, myRecordName: "me", myName: nil, guideName: nil) == nil)
    }
}
