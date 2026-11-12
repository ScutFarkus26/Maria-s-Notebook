import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// Children away with a co-teacher on the Scheduled cards, the day's badge,
/// the card's time picker and the lesson's sheet (docs/Plans/Plan - Co-teacher
/// times when scheduling.md, Phase 3, decisions 4–6). Its own fixtures:
/// made-up last names, never the roster's.
@Suite("Away with a co-teacher on the cards")
@MainActor
struct AwayOnCardsTests {

    private typealias Support = TimetableTestSupport

    var calendar: Calendar { AppCalendar.shared }
    /// Monday 26 October 2026, a school day.
    var monday: Date { Support.monday }

    func minutes(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    func at(_ hour: Int, _ minute: Int) -> Date {
        DayHalfPlanner.settingTime(hour: hour, minute: minute, on: monday, using: calendar)
    }

    func slot(_ rank: Int, _ period: DayPeriod) -> Date {
        DayHalfPlanner.slot(rank, in: period, on: monday, using: calendar)
    }

    // MARK: - Fixture

    /// The children, in a store, with short names "Lucy T", "Ora P", "Naomi F".
    struct Class {
        let context: NSManagedObjectContext
        let students: [CDStudent]
        let lucy: UUID
        let ora: UUID
        let naomi: UUID
    }

    func makeClass() throws -> Class {
        let context = try CoreDataTestHelpers.makeContext()
        let students = [("Lucy", "Tamir"), ("Ora", "Peled"), ("Naomi", "Fishel")].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0.0, lastName: $0.1)
        }
        let ids = try students.map { try #require($0.id) }
        return Class(context: context, students: students, lucy: ids[0], ora: ids[1], naomi: ids[2])
    }

    /// Monday as it really runs, plus one afternoon group: Miss Nicole's Book
    /// Club 9:15–9:45 (Lucy, Ora), Morah Devora's 9:50–10:20 (Lucy) and
    /// 10:40–11:10 (Ora), and 1:30–2:00 (Naomi).
    func realMonday(_ kids: Class) -> AwayDay {
        func block(_ person: String, _ start: Int, _ title: String, _ children: [UUID]) -> AwayBlock {
            AwayBlock(
                blockID: UUID(), personName: person, title: title, startMinute: start, endMinute: start + 30,
                studentIDs: AwayDay.keys(children)
            )
        }
        return AwayDay(blocks: [
            block("Miss Nicole", minutes(9, 15), "Book Club", [kids.lucy, kids.ora]),
            block("Morah Devora", minutes(9, 50), "Chumash", [kids.lucy]),
            block("Morah Devora", minutes(10, 40), "Navi", [kids.ora]),
            block("Morah Devora", minutes(13, 30), "Parsha", [kids.naomi])
        ])
    }

    func planned(at date: Date, children: [UUID], in context: NSManagedObjectContext) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.id = UUID()
        assignment.createdAt = monday
        assignment.studentIDs = children.map(\.uuidString)
        assignment.schedule(for: date)
        return assignment
    }

    func column(
        for day: [CDLessonAssignment],
        students: [CDStudent],
        away: AwayDay,
        kinds: CalendarKindFilter = .everything,
        lessons: [CDLesson] = [],
        width: CGFloat = WeekPlanSection.minimumColumnWidth
    ) -> WeekDayColumn {
        WeekDayColumn(
            day: monday,
            allLessonAssignments: day,
            scheduledLessons: LessonAssignmentOrdering.sorted(day, using: calendar),
            lessons: lessons,
            students: students,
            visibleKinds: kinds,
            checkInGroups: [],
            focusedPresentationID: nil,
            onClear: { _ in },
            onSelect: { _ in },
            onOpenCheckInGroup: { _ in },
            onDropWorkCheckIns: { _, _ in },
            onDropWork: { _, _ in },
            pillActions: WorkCheckPillActions(
                rows: { _ in [] }, children: { _ in [] }, log: { _, _, _ in }, openWork: { _ in }
            ),
            columnWidth: width,
            awayDay: away
        )
    }

    // MARK: - The chip and the line

    @Test("A set time a group overlaps: amber chip and the leaving line; already there: the until line")
    func timedClash() throws {
        let kids = try makeClass()
        let leaving = planned(at: at(9, 45), children: [kids.lucy], in: kids.context)
        let there = planned(at: at(10, 0), children: [kids.lucy], in: kids.context)
        let both = planned(at: at(9, 30), children: [kids.lucy], in: kids.context)
        let pair = planned(at: at(9, 20), children: [kids.lucy, kids.ora], in: kids.context)
        let many = planned(at: at(9, 40), children: [kids.lucy, kids.ora, kids.naomi], in: kids.context)
        let col = column(
            for: [leaving, there, both, pair, many], students: kids.students, away: realMonday(kids)
        )
        let names = col.awayNames

        let chip = col.timeChip(for: leaving, sameTimeClashes: [], awayNames: names)
        #expect(chip.away == AwayOnCards.Note(line: "Lucy T leaves at 9:50 for Morah Devora", isClash: true))
        #expect(chip.isAwayClash)
        #expect(!chip.isClash, "not the same-time kind")
        #expect(PresentationPlannerCard.TimeChipStyle(chip) == .clash)

        #expect(col.awayNote(for: there, names: names)?.line == "Lucy T is with Morah Devora until 10:20")
        #expect(col.awayNote(for: both, names: names)?.line == "Lucy T is away during this lesson")
        #expect(col.awayNote(for: pair, names: names)?.line == "Lucy T and Ora P are with Miss Nicole until 9:45")
        // Naomi is in no morning group: two of the three children, in two groups.
        #expect(col.awayNote(for: many, names: names)?.line == "2 children are away during this lesson")
    }

    @Test("No set time: a quiet note for the half, never a clash")
    func untimedNote() throws {
        let kids = try makeClass()
        let afternoon = planned(at: slot(0, .afternoon), children: [kids.naomi], in: kids.context)
        let morning = planned(at: slot(0, .morning), children: [kids.lucy], in: kids.context)
        let twoKids = planned(at: slot(1, .morning), children: [kids.lucy, kids.ora], in: kids.context)
        let col = column(for: [afternoon, morning, twoKids], students: kids.students, away: realMonday(kids))
        let names = col.awayNames

        let chip = col.timeChip(for: afternoon, sameTimeClashes: [], awayNames: names)
        #expect(chip.away == AwayOnCards.Note(line: "Naomi F is away 1:30–2:00", isClash: false))
        #expect(!chip.isAwayClash)
        #expect(PresentationPlannerCard.TimeChipStyle(chip) == .unset)
        #expect(col.awayNote(for: morning, names: names)?.line == "Lucy T is away part of the morning")
        #expect(col.awayNote(for: twoKids, names: names)?.line == "2 children are away part of the morning")
        #expect(col.awayClashCount == 0, "untimed lessons don't count on the badge")
    }

    @Test("A clear lesson, an empty day or a child in no group: no line, the chip as it was")
    func clear() throws {
        let kids = try makeClass()
        let clear = planned(at: at(10, 20), children: [kids.lucy], in: kids.context)
        let naomiMorning = planned(at: at(9, 0), children: [kids.naomi], in: kids.context)
        let col = column(for: [clear, naomiMorning], students: kids.students, away: realMonday(kids))
        #expect(col.awayNote(for: clear, names: col.awayNames) == nil, "10:20 starts as the group ends")
        #expect(col.awayNote(for: naomiMorning, names: col.awayNames) == nil)
        let chip = col.timeChip(for: clear, sameTimeClashes: [], awayNames: col.awayNames)
        #expect(PresentationPlannerCard.TimeChipStyle(chip) == .set)

        let empty = column(for: [clear], students: kids.students, away: .empty)
        #expect(empty.awayNote(for: clear, names: [:]) == nil)
        #expect(empty.awayNames.isEmpty, "no roster lookup on a day nobody is away")
        #expect(empty.pickerAway(for: clear) == nil)
    }

    // MARK: - The day's badge

    @Test("The badge counts each timed lesson with a child away, and is plain when nothing else clashes")
    func badge() throws {
        let kids = try makeClass()
        let day = [
            planned(at: at(9, 45), children: [kids.lucy], in: kids.context),
            planned(at: at(10, 45), children: [kids.ora], in: kids.context),
            planned(at: at(11, 0), children: [kids.naomi], in: kids.context),
            planned(at: slot(0, .afternoon), children: [kids.lucy], in: kids.context)
        ]
        let col = column(for: day, students: kids.students, away: realMonday(kids))
        #expect(col.awayClashCount == 2)
        let clashes = col.dayClashes
        #expect(clashes.away == 2)
        #expect(clashes.children == 0)
        #expect(clashes.total == 2)
        #expect(clashes.badgeText == "2 clashes")
        #expect(clashes.spokenLabel == "2 lessons while a child is with another teacher.")
        #expect(clashes.plainHelp == "2 lessons while a child is with another teacher. Change their times to clear it.")

        let one = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [570], awayClashes: 1)
        #expect(one.spokenLabel == "1 lesson while a child is with another teacher.")
        #expect(one.plainHelp == "1 lesson while a child is with another teacher. Change its time to clear it.")
    }

    @Test("Both kinds on one plain badge are counted apart, in the same-time words first")
    func badgeBothKinds() {
        let both = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [570, 570, 600], awayClashes: 2)
        #expect(both.total == 3)
        #expect(both.spokenLabel == "2 lessons at the same time, 2 with a child away.")
        #expect(both.plainHelp == "2 lessons at the same time, 2 with a child away. Change one of the times.")

        let sameOnly = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [570, 570])
        #expect(sameOnly.plainHelp == "Two lessons start at the same time. Change one of the times.", "unchanged")

        let withChild = WeekDayColumn.dayClashes(
            childClashes: [.morning: [UUID()]], setMinutes: [600], awayClashes: 1
        )
        #expect(withChild.total == 2)
        #expect(withChild.spokenLabel
            == "1 child booked twice in the same half, 1 lesson while a child is with another teacher. "
                + "Rearrange this day.")
    }

    // MARK: - VoiceOver

    @Test("The chip says a child is with another teacher, never another lesson, and the card speaks the line")
    func spokenWords() {
        let clash = PresentationPlannerCard.spokenLabel(
            lessonName: "Commutative Law", studentNames: ["Lucy T"], period: .morning,
            timeChip: .init(
                time: LessonClockTime(hour: 9, minute: 45),
                away: AwayOnCards.Note(line: "Lucy T leaves at 9:50 for Morah Devora", isClash: true)
            ),
            showFirstLine: nil
        )
        #expect(clash.contains(AwayText.chipSpoken))
        #expect(!clash.contains("another lesson at the same time"))
        #expect(clash.hasSuffix("a child is with another teacher then, Lucy T leaves at 9:50 for Morah Devora"))

        let untimed = PresentationPlannerCard.spokenLabel(
            lessonName: "Parts of Speech", studentNames: ["Naomi F"], period: .afternoon,
            timeChip: .init(time: nil, away: AwayOnCards.Note(line: "Naomi F is away 1:30–2:00", isClash: false)),
            showFirstLine: nil
        )
        #expect(untimed == "Parts of Speech, Naomi F, Afternoon, Naomi F is away 1:30–2:00")
        #expect(AwayText.legend == "A child is with another teacher")
    }

    // MARK: - The card's picker

    @Test("A card's picker lists the groups, marks the times they overlap and offers the free starts")
    func pickerForACard() throws {
        let kids = try makeClass()
        let lesson = planned(at: slot(0, .morning), children: [kids.lucy], in: kids.context)
        let other = planned(at: at(13, 0), children: [kids.ora], in: kids.context)
        let col = column(for: [lesson, other], students: kids.students, away: realMonday(kids))
        let away = try #require(col.pickerAway(for: lesson))

        #expect(away.rows == [
            "9:15–9:45 · Lucy T · Miss Nicole",
            "9:50–10:20 · Lucy T · Morah Devora"
        ])
        #expect(away.sentences[minutes(8, 45)] == nil)
        #expect(away.sentences[minutes(9, 0)] == "Lucy T leaves at 9:15 for Miss Nicole")
        #expect(away.sentences[minutes(9, 15)] == "Lucy T is with Miss Nicole until 9:45")
        #expect(away.sentences[minutes(9, 30)] == "Lucy T is away during this lesson")
        #expect(away.sentences[minutes(9, 45)] == "Lucy T leaves at 9:50 for Morah Devora")
        #expect(away.sentences[minutes(10, 15)] == "Lucy T is with Morah Devora until 10:20")
        #expect(away.sentences[minutes(10, 30)] == nil)
        #expect(Set(away.sentences.keys).isSubset(of: Set(LessonTimeChoices.morning)))
        #expect(away.suggestions == [minutes(8, 45), minutes(10, 20)])
        #expect(away.freeWords == "Free all afternoon")

    }

    @Test("The free starts keep clear of the day's other set times")
    func pickerKeepsClearOfOwnLessons() throws {
        let kids = try makeClass()
        let other = planned(at: at(13, 0), children: [kids.ora], in: kids.context)
        let naomi = planned(at: slot(1, .afternoon), children: [kids.naomi], in: kids.context)
        let col = column(for: [naomi, other], students: kids.students, away: realMonday(kids))
        let naomiAway = try #require(col.pickerAway(for: naomi))
        #expect(naomiAway.freeWords == "Free all morning")
        // 1:00 is the other lesson's, so the first start free of both is 2:00.
        #expect(naomiAway.suggestions == [minutes(14, 0)])
    }

    @Test("Show set to presentations only: the cards still get their away times")
    func presentationsOnly() throws {
        let kids = try makeClass()
        let lesson = planned(at: at(9, 45), children: [kids.lucy], in: kids.context)
        let col = column(for: [lesson], students: kids.students, away: realMonday(kids), kinds: .presentations)
        #expect(col.awayClashCount == 1)
        #expect(col.dayClashes.away == 1)
        #expect(col.awayNote(for: lesson, names: col.awayNames)?.isClash == true)
        let hidden = column(for: [lesson], students: kids.students, away: realMonday(kids), kinds: .work)
        #expect(hidden.dayClashes.total == 0, "no badge for lessons the guide can't see")
    }
}
