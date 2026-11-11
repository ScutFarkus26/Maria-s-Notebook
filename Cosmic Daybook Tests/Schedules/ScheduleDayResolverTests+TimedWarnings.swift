import Foundation
import Testing
@testable import CosmicDaybook

/// Rule 6 for a lesson with a set time: a child with another teacher warns
/// only when the lesson's 30 minutes overlap the group (plan "Co-teacher
/// times when scheduling", decision 7).
private typealias Support = TimetableTestSupport

extension ScheduleDayResolverTests {

    @Test("A timed lesson warns only when its 30 minutes overlap the group, with the lesson's time")
    func timedLessonWarnsExactly() {
        let group = Support.block(
            Support.devora, .monday, Support.minutes(9, 50), 30, "Chumash", children: [Support.lucy]
        )
        let names = [Support.lucy: "Lucy T"]
        func texts(_ minute: Int) -> [String] {
            let lesson = ScheduleLessonSnapshot(
                id: UUID(), title: "Fractions", half: .morning, minute: minute, studentIDs: [Support.lucy]
            )
            return Support.resolve(Support.monday, blocks: [group], lessons: [lesson]).warnings
                .map { $0.text { names[$0] } }
        }
        #expect(texts(Support.minutes(9, 45)) == ["Lucy T is with Morah Devora 9:50–10:20, during your 9:45 lesson."])
        #expect(texts(Support.minutes(10, 15)) == ["Lucy T is with Morah Devora 9:50–10:20, during your 10:15 lesson."])
        #expect(texts(Support.minutes(9, 20)).isEmpty, "it ends as the group starts")
        #expect(texts(Support.minutes(10, 20)).isEmpty, "it starts as the group ends")
        #expect(texts(Support.minutes(9)).isEmpty, "same morning, no overlap")
        // An untimed lesson keeps the half rule.
        let untimed = ScheduleLessonSnapshot(id: UUID(), title: "Maps", half: .morning, studentIDs: [Support.lucy])
        let day = Support.resolve(Support.monday, blocks: [group], lessons: [untimed])
        #expect(day.warnings.map { $0.text { names[$0] } } == ["Lucy T is with Morah Devora 9:50–10:20 this morning."])
    }

    @Test("A clear timed lesson first doesn't hide a later lesson in the same half that clashes")
    func everyLessonIsChecked() {
        let group = Support.block(
            Support.devora, .monday, Support.minutes(9, 50), 30, "Chumash", children: [Support.lucy]
        )
        let clear = ScheduleLessonSnapshot(
            id: UUID(), title: "Fractions", half: .morning, minute: Support.minutes(8, 45), order: 0,
            studentIDs: [Support.lucy]
        )
        let clashing = ScheduleLessonSnapshot(
            id: UUID(), title: "Maps", half: .morning, minute: Support.minutes(10), order: 1,
            studentIDs: [Support.lucy, Support.ari]
        )
        let day = Support.resolve(Support.monday, blocks: [group], lessons: [clear, clashing])
        #expect(day.warnings.count == 1)
        #expect(day.warnings.first?.lessonID == clashing.id)
        let names = [Support.lucy: "Lucy T"]
        #expect(day.warnings.first?.text { names[$0] }
            == "Lucy T is with Morah Devora 9:50–10:20, during your 10:00 lesson.")
        // Two clashing lessons still give one warning per child and group.
        let alsoClashing = ScheduleLessonSnapshot(
            id: UUID(), title: "Art", half: .morning, order: 2, studentIDs: [Support.lucy]
        )
        let both = Support.resolve(Support.monday, blocks: [group], lessons: [clear, clashing, alsoClashing])
        #expect(both.warnings.map(\.lessonID) == [clashing.id])
    }
}
