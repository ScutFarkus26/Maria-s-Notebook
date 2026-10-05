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
    func markerNames() throws {
        let assistant = "assistant"
        let guide = "leadGuide"
        func who(
            _ row: Model.Row, mine: String? = "me", myName: String? = "Rivka", guideName: String? = nil
        ) -> String? {
            Model.markerName(for: row, myRecordName: mine, myName: myName, guideName: guideName)
        }

        #expect(who(try row(by: assistant, id: "me", name: "Rivka")) == "you")
        #expect(who(try row(by: assistant, id: "other", name: "Chana")) == "Chana")
        // Without her record name, the typed name decides.
        #expect(who(try row(by: assistant, name: "Rivka"), mine: nil) == "you")

        let guideMark = try row(by: guide)
        #expect(who(guideMark) == "your guide")
        #expect(who(guideMark, guideName: "Danny") == "Danny")

        #expect(who(try row(.unmarked, by: assistant, id: "me"), myName: nil) == nil)
        #expect(who(try row(by: nil), myName: nil) == nil)
    }

    @Test("Marked by and the front-desk line read the classroom's list, and a reload follows a rename")
    func namesFromTheList() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let today = Calendar.current.startOfDay(for: Date())
        func mark(_ first: String, by role: String, id: String, name: String?) {
            let student = AssistantTestSupport.student(first, "Cedar", in: context)
            let record = CDAttendanceRecord(context: context)
            record.studentID = student.id!.uuidString
            record.date = today
            record.status = .present
            record.recordedBy = role
            record.recordedByID = id
            record.recordedByName = name
        }
        mark("Ari", by: "leadGuide", id: "_guide", name: nil)
        mark("Leah", by: "assistant", id: "_chana", name: "Chana")
        let send = CDAttendanceEmailSend(context: context)
        send.date = today
        send.sentAt = Date()
        send.sentBy = CDClassroomMembership.ClassroomRole.leadGuide.rawValue
        send.sentByID = "_guide"
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack)
        func who(_ first: String) throws -> String? {
            let row = try #require(model.rows.first { $0.student.firstName == first })
            return Model.markerName(
                for: row, myRecordName: "me", myName: "Rivka", guideName: "Daniel DeBerry", names: model.names
            )
        }
        func sender() throws -> String {
            try #require(model.frontDesk.latestSend).senderName(
                viewerRole: .assistant, myRecordName: "me", myName: "Rivka",
                guideName: "Daniel DeBerry", names: model.names
            )
        }
        // No names set: Apple's name for the guide, the name Chana's mark was stamped with.
        #expect(try who("Ari") == "Daniel DeBerry")
        #expect(try who("Leah") == "Chana")
        #expect(try sender() == "Daniel DeBerry")

        AssistantRestockTestSupport.person("_guide", "Danny", role: .leadGuide, in: context)
        AssistantRestockTestSupport.person("_chana", "Hannah", in: context)
        model.load()
        #expect(model.names.guideName == "Danny")
        #expect(try who("Ari") == "Danny")
        #expect(try who("Leah") == "Hannah")
        #expect(try sender() == "Danny")
    }

    @Test("A locked day's long-press still says the mark and who made it, or that there's none")
    func lockedDayHeader() throws {
        let eight = try #require(Calendar.current.date(bySettingHour: 8, minute: 2, second: 0, of: Date()))
        let marked = try row(by: "leadGuide", at: eight)
        let header = AttendanceTile.readOnlyHeader(for: marked, markedBy: "your guide")
        #expect(header.hasPrefix("Present"))
        #expect(header.hasSuffix("by your guide"))
        #expect(header == AttendanceStatusMenu.header(for: marked, markedBy: "your guide"))

        #expect(AttendanceTile.readOnlyHeader(for: try row(.unmarked, by: nil), markedBy: nil) == "Not marked")
        #expect(!AttendanceTile.lockedLine.isEmpty)
    }
}
