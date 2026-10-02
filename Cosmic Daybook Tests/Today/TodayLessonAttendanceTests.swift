import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Today lesson rows: who is here")
struct TodayLessonAttendanceTests {
    private let maya = UUID()
    private let theo = UUID()
    private let ava = UUID()
    private let leo = UUID()

    @Test("Absent children are marked, in the lesson's own order")
    func absentChildrenAreMarked() {
        let attendance = TodayLessonAttendance(studentIDs: [maya, theo, ava], absent: [theo, leo])
        #expect(attendance.children.map(\.id) == [maya, theo, ava])
        #expect(attendance.children.map(\.isAbsent) == [false, true, false])
        #expect(attendance.absentIDs == [theo])
        #expect(attendance.hasAbsent)
    }

    @Test("Some absent reads \"N of M here\"")
    func someAbsent() {
        let attendance = TodayLessonAttendance(studentIDs: [maya, theo, ava, leo], absent: [theo])
        #expect(attendance.hereText == "3 of 4 here")
    }

    @Test("Everyone present reads \"all N here\"")
    func everyonePresent() {
        let attendance = TodayLessonAttendance(studentIDs: [maya, theo, ava, leo], absent: [])
        #expect(attendance.hereText == "all 4 here")
        #expect(attendance.hasAbsent == false)
    }

    @Test("Everyone absent reads \"0 of N here\"")
    func everyoneAbsent() {
        let attendance = TodayLessonAttendance(studentIDs: [maya, theo], absent: [maya, theo])
        #expect(attendance.hereText == "0 of 2 here")
    }

    @Test("A lesson of one says \"here\"; a lesson of none says nothing")
    func smallLessons() {
        #expect(TodayLessonAttendance(studentIDs: [maya], absent: []).hereText == "here")
        #expect(TodayLessonAttendance(studentIDs: [maya], absent: [maya]).hereText == "0 of 1 here")
        #expect(TodayLessonAttendance(studentIDs: [], absent: [maya]).hereText == nil)
    }

    @Test("The header counts each absent child once across the day's lessons")
    func headerCountsDistinctChildren() {
        let absent = TodayLessonAttendance.absentChildren(
            onLessons: [[maya, theo], [theo, ava], [leo]],
            absent: [theo, leo, UUID()]
        )
        #expect(absent == [theo, leo])
        #expect(TodayLessonAttendance.absentSummary(count: 1) == "1 child on today's lessons is absent")
        #expect(TodayLessonAttendance.absentSummary(count: 3) == "3 children on today's lessons are absent")
        #expect(TodayLessonAttendance.givenText(given: 0, total: 4) == "0 of 4 given")
    }
}
