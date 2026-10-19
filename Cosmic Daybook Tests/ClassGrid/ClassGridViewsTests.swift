import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The Class Grid's three newer views, below the screen: Three Years groups children
/// by year in class, oldest first; Children narrows to an area and says where a child
/// stands; Recall's queue follows the area, the search and the children filter.
@Suite("Class Grid views")
@MainActor
struct ClassGridViewsTests {

    private func column(_ name: String, year: Int, started: TimeInterval?) -> ClassColumn {
        ClassColumn(
            student: CurriculumStudentRef(
                id: UUID(), firstName: name, lastName: "Test", nickname: nil, levelRaw: "Upper",
                dateStarted: started.map { Date(timeIntervalSince1970: $0) }, isEnrolled: true
            ),
            year: year
        )
    }

    @Test("Three Years: Year 3 first, then each year's children by start date, in labeled blocks")
    func yearBlocks() {
        let columns = [
            column("Ora", year: 1, started: 1_790_000_000),
            column("Dalia", year: 3, started: 1_720_000_000),
            column("Avital", year: 2, started: 1_760_000_000),
            column("Avigail", year: 3, started: 1_710_000_000),
            column("Naomi", year: 1, started: nil)
        ].sorted(by: ClassGridYearsModel.cohortOrder)
        #expect(columns.map(\.student.firstName) == ["Avigail", "Dalia", "Avital", "Ora", "Naomi"])

        let (blocks, starts) = ClassGridYearsModel.blocks(for: columns)
        #expect(blocks.map(\.title) == ["YEAR 3 · 2", "YEAR 2 · 1", "YEAR 1 · 2"])
        #expect(starts == [columns[2].id, columns[3].id])
    }

    @Test("Three Years: the Not yet column counts the children with nothing recorded")
    func notYetColumn() {
        let columns = [column("A", year: 1, started: nil), column("B", year: 1, started: nil)]
        let row = ClassRow(
            kind: .lesson(UUID()), title: "Laws", subtitle: nil, tint: .blue, lessonIDs: [UUID()],
            cells: [columns[0].id: CurriculumGlyphSpec(state: .presented, recall: nil)],
            counts: [:]
        )
        #expect(row.notYetText(over: columns) == "1 not yet")
        #expect(row.notYetText(over: [columns[0]]) == "Everyone")
    }

    @Test("Children: where a child stands, and her strips in one area only")
    func childCard() {
        let pills = [
            LessonPillState(id: UUID(), lessonID: UUID(), name: "A", status: .mastered, orderInSequence: 0),
            LessonPillState(id: UUID(), lessonID: UUID(), name: "B", status: .practicing, orderInSequence: 1),
            LessonPillState(id: UUID(), lessonID: UUID(), name: "C", status: .notReady, orderInSequence: 2)
        ]
        let id = UUID()
        let math = SubjectProgression(id: "m", area: "Math", sequences: [
            SequenceProgression(id: "s", studentID: id, area: "Math", sequence: "Stamp Game", pills: pills)
        ])
        let language = SubjectProgression(id: "l", area: "Language", sequences: [
            SequenceProgression(id: "g", studentID: id, area: "Language", sequence: "Grammar", pills: [pills[0]])
        ])
        let card = StudentProgressionCard(
            id: id, firstName: "Maya", lastName: "Stone", nickname: nil, level: .upper, yearInClass: 2,
            subjects: [math, language]
        )
        #expect(card.initials == "MS")
        #expect(card.subtitle == "Upper · Year 2 · 2 areas")
        #expect(card.masteredText == "2 lessons mastered")
        #expect(math.sequences[0].presentedCount == 2)
        #expect(card.keepingSubjects { $0.area == "Language" }.subjects.map(\.area) == ["Language"])
    }

    @Test("A student-page status reads as the Class Grid's mark")
    func nodeStatusMapping() {
        #expect(ChecklistDisplayStatus(LessonNodeStatus.notStarted) == .notReady)
        #expect(ChecklistDisplayStatus(LessonNodeStatus.scheduled(nil)) == .planned)
        #expect(ChecklistDisplayStatus(LessonNodeStatus.scheduled(Date())) == .planned)
        #expect(ChecklistDisplayStatus(LessonNodeStatus.reviewing) == .reviewing)
        #expect(ChecklistDisplayStatus(LessonNodeStatus.mastered) == .mastered)
    }

    @Test("Recall: the queue follows the area, the search and the children filter")
    func recallFilter() {
        let maya = UUID()
        let eli = UUID()
        func entry(_ student: UUID, _ lesson: String, area: String) -> RecallQueueEntry {
            RecallQueueEntry(
                id: "\(student)|\(lesson)", studentID: student.uuidString, area: area, sequence: "Seq",
                frontierLessonID: UUID(), frontierLessonName: lesson, frontierOrderInSequence: 0,
                frontierMasteredAt: nil, coveredLessons: [], lastCheckedAt: nil, dueReason: .startOfYearSweep
            )
        }
        let sections = [
            RecallStudentSection(id: maya.uuidString, studentName: "Maya Stone", entries: [
                entry(maya, "Division: Static", area: "Math"), entry(maya, "The Verb", area: "Language")
            ]),
            RecallStudentSection(id: eli.uuidString, studentName: "Eli Park", entries: [
                entry(eli, "Types of Angles", area: "Geometry")
            ])
        ]
        let all = RecallQueueFilter.sections(sections, area: nil, query: "", childIDs: [])
        #expect(all.flatMap(\.entries).count == 3)

        let math = RecallQueueFilter.sections(sections, area: " math ", query: "", childIDs: [])
        #expect(math.map(\.studentName) == ["Maya Stone"])
        #expect(math.flatMap(\.entries).map(\.frontierLessonName) == ["Division: Static"])

        let verb = RecallQueueFilter.sections(sections, area: nil, query: "verb", childIDs: [])
        #expect(verb.flatMap(\.entries).map(\.frontierLessonName) == ["The Verb"])

        let eliOnly = RecallQueueFilter.sections(sections, area: nil, query: "", childIDs: [eli])
        #expect(eliOnly.map(\.studentName) == ["Eli Park"])
    }

    @Test("Recall: what each outcome does, in plain words")
    func recallOutcomeWords() {
        #expect(RecallCheckText.consequence(of: .retained, coversCount: 4)
            == "Updates when mastery was last seen, and marks the 4 lessons it covers as kept. Mastery isn't changed.")
        #expect(RecallCheckText.consequence(of: .retained, coversCount: 0)
            == "Updates when mastery was last seen. Mastery isn't changed.")
        #expect(RecallCheckText.consequence(of: .shaky, coversCount: 2)
            == "Adds a follow-up: more practice on this lesson. Mastery isn't changed.")
        #expect(RecallCheckText.outcomes.map(RecallCheckText.title) == ["Still has it", "Shaky", "Forgotten"])
    }
}
