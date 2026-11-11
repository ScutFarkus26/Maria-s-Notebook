import Foundation
import Testing
@testable import CosmicDaybook

/// What the Schedules block sheet's Save writes (`ScheduleBlockSheet.Fields`):
/// only the fields Danny changed, so a field the sheet doesn't show, or shows
/// rounded or reordered, keeps its stored value, and Save with nothing changed
/// changes nothing.
@Suite("Schedules: the block sheet's Save")
@MainActor
struct ScheduleBlockSheetTests {

    private typealias Support = TimetableTestSupport
    private typealias Fields = ScheduleBlockSheet.Fields

    private let lucy = UUID()
    private let ari = UUID()
    private let bea = UUID()

    /// The order the student picker lists them in.
    private var studentOrder: [UUID] { [lucy, ari, bea] }

    @Test("Save with nothing changed changes nothing: a room's children, an odd length, the children's order")
    func nothingChanged() {
        let room = TimetableBlockValues(
            startMinute: Support.minutes(10, 30), lengthMinutes: 47, title: " Math ", note: "Bring rulers",
            teacherLaneID: Support.guide.id, teacherName: "Mr. Adler", studentIDs: [bea.uuidString, ari.uuidString]
        )
        #expect(Fields(room).edit(from: room, laneKind: .room, studentOrder: studentOrder).isEmpty)

        let person = TimetableBlockValues(
            startMinute: Support.minutes(9), lengthMinutes: 600, title: "Chumash", teacherName: "Morah Devora",
            studentIDs: [bea.uuidString, "not-an-id", lucy.uuidString.lowercased()]
        )
        #expect(Fields(person).edit(from: person, laneKind: .person, studentOrder: studentOrder).isEmpty)
        // The sheet shows what it can: the length on its own scale, the children it can name.
        #expect(Fields(person).length == 480)
        #expect(Fields(person).childIDs == [bea, lucy])
    }

    @Test("A change to one field sets that field only")
    func oneFieldChanged() {
        let block = TimetableBlockValues(
            startMinute: Support.minutes(9), lengthMinutes: 47, title: "Math", studentIDs: [bea.uuidString]
        )
        var fields = Fields(block)
        fields.title = "  Mathematics "
        #expect(fields.edit(from: block, laneKind: .room, studentOrder: studentOrder)
            == TimetableService.BlockEdit(title: "Mathematics"))
        let saved = fields.edit(from: block, laneKind: .room, studentOrder: studentOrder).applied(to: block)
        #expect(saved.lengthMinutes == 47)
        #expect(saved.studentIDs == [bea.uuidString], "a room's children stay")

        fields = Fields(block)
        fields.length = ScheduleBlockSheet.stepped(fields.length, by: 1)
        fields.startMinute = Support.minutes(9, 15)
        #expect(fields.edit(from: block, laneKind: .room, studentOrder: studentOrder)
            == TimetableService.BlockEdit(startMinute: Support.minutes(9, 15), lengthMinutes: 50))
    }

    @Test("Who teaches is written for a room only, and only when it changed")
    func teacher() {
        let block = TimetableBlockValues(startMinute: Support.minutes(9), title: "Navi", teacherName: " Mr. Adler ")
        var fields = Fields(block)
        #expect(fields.teacher == .someoneElse)
        fields.teacherName = "Mr. Adler"
        #expect(fields.edit(from: block, laneKind: .room, studentOrder: studentOrder).isEmpty, "only spaces differ")

        fields.teacher = .lane(Support.devora.id)
        #expect(fields.edit(from: block, laneKind: .room, studentOrder: studentOrder).teacher
            == TimetableService.BlockEdit.Teacher(laneID: Support.devora.id, name: ""))
        #expect(fields.edit(from: block, laneKind: .person, studentOrder: studentOrder).isEmpty,
                "a person's block shows no teacher, so it keeps its own")
    }

    @Test("Children chosen keep their order; new ones join after, in the picker's order")
    func children() {
        let block = TimetableBlockValues(
            startMinute: Support.minutes(9), title: "Chumash", studentIDs: [bea.uuidString, "not-an-id", ari.uuidString]
        )
        var fields = Fields(block)
        fields.childIDs = [ari, bea, lucy]
        #expect(fields.edit(from: block, laneKind: .person, studentOrder: studentOrder).studentIDs
            == [bea.uuidString, "not-an-id", ari.uuidString, lucy.uuidString])

        fields.childIDs = [ari]
        #expect(fields.edit(from: block, laneKind: .person, studentOrder: studentOrder).studentIDs
            == ["not-an-id", ari.uuidString])
        #expect(fields.edit(from: block, laneKind: .room, studentOrder: studentOrder).isEmpty,
                "a room's block shows no children, so it keeps its own")
    }

    @Test("A new block takes the sheet's fields over the starting values")
    func newBlock() {
        let start = TimetableBlockValues(startMinute: Support.minutes(9))
        var fields = Fields(start)
        fields.title = "Recess"
        fields.childIDs = [bea, lucy]
        let values = fields.edit(from: start, laneKind: .person, studentOrder: studentOrder).applied(to: start)
        #expect(values == TimetableBlockValues(
            startMinute: Support.minutes(9), lengthMinutes: 30, title: "Recess",
            studentIDs: [lucy.uuidString, bea.uuidString]
        ))
    }

    @Test("The length steps onto the five-minute marks, within 5 minutes and 8 hours")
    func lengthSteps() {
        #expect(ScheduleBlockSheet.stepped(47, by: 1) == 50)
        #expect(ScheduleBlockSheet.stepped(47, by: -1) == 45)
        #expect(ScheduleBlockSheet.stepped(45, by: 1) == 50)
        #expect(ScheduleBlockSheet.stepped(45, by: -1) == 40)
        #expect(ScheduleBlockSheet.stepped(5, by: -1) == 5)
        #expect(ScheduleBlockSheet.stepped(480, by: 1) == 480)
        #expect(ScheduleBlockSheet.lengthText(47) == "47 min")
    }

    // MARK: - When the block ends, and names typed in

    @Test("The Length row says when the block ends: across noon, and past an hour")
    func lengthRowEnds() {
        #expect(ScheduleBlockSheet.lengthRowText(startMinute: Support.minutes(9, 50), length: 30)
            == "30 min · ends 10:20")
        #expect(ScheduleBlockSheet.lengthRowText(startMinute: Support.minutes(11, 50), length: 45)
            == "45 min · ends 12:35")
        #expect(ScheduleBlockSheet.lengthRowText(startMinute: Support.minutes(12, 30), length: 60)
            == "1 hr · ends 1:30")
        #expect(ScheduleBlockSheet.lengthRowText(startMinute: Support.minutes(9), length: 75)
            == "1 hr 15 min · ends 10:15")
    }

    private var roster: [StudentNameMatcher.Candidate] {
        [
            .init(id: lucy, firstName: "Lucy", lastName: "Tanner", nickname: nil),
            .init(id: ari, firstName: "Ari", lastName: "Stone", nickname: nil),
            .init(id: bea, firstName: "Bea", lastName: "Klein", nickname: nil)
        ]
    }

    @Test("Save sorts the names still in the field: the last one, typed without a comma, is added")
    func saveSortsTheField() {
        let block = TimetableBlockValues(
            startMinute: Support.minutes(9), title: "Chumash", studentIDs: [bea.uuidString]
        )
        var fields = Fields(block)
        var names = ScheduleNameEntry(text: "Ari, Lucy T")
        #expect(ScheduleBlockSheet.sortNamesBeforeSave(
            &names, into: &fields.childIDs, laneKind: .person, students: roster
        ))
        #expect(names.text.isEmpty)
        #expect(fields.edit(from: block, laneKind: .person, studentOrder: studentOrder).studentIDs
            == [bea.uuidString, lucy.uuidString, ari.uuidString])
    }

    @Test("Save with a name that fits nobody keeps the sheet open and saves nothing")
    func saveKeepsAnUnmatchedName() {
        let block = TimetableBlockValues(
            startMinute: Support.minutes(9), title: "Chumash", studentIDs: [bea.uuidString]
        )
        var fields = Fields(block)
        var names = ScheduleNameEntry(text: "Vivi")
        #expect(!ScheduleBlockSheet.sortNamesBeforeSave(
            &names, into: &fields.childIDs, laneKind: .person, students: roster
        ))
        #expect(names.text == "Vivi")
        #expect(names.unmatched == [.init(name: "Vivi", reason: .nobody)])
        #expect(fields.edit(from: block, laneKind: .person, studentOrder: studentOrder).isEmpty)

        // A room's block has no names field: its Save goes on.
        #expect(ScheduleBlockSheet.sortNamesBeforeSave(
            &names, into: &fields.childIDs, laneKind: .room, students: roster
        ))
    }
}
