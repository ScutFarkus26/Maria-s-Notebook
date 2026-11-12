import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// `AwayOnCardsTests`' pictures of a day's list with the three card states:
/// a set time a group overlaps, a lesson with no set time while a child is
/// away that half, and a clear one. `dayList` is drawn rather than the
/// column, whose `ScrollView` `ImageRenderer` draws blank. Saved, when the run
/// asks (`TEST_RUNNER_LESSON_TIME_SHOT_DIR`), as `away-cards-<device>-<scheme>.png`;
/// the plan keeps them in `docs/Pictures/Co-teacher times/`.
extension AwayOnCardsTests {

    @Test("Pictures: a clashing card, an untimed card with its note and a clear card, at iPad and iPhone width")
    func pictures() throws {
        let kids = try makeClass()
        func lesson(_ name: String, _ area: String) -> CDLesson {
            CoreDataTestHelpers.seedLesson(in: kids.context, name: name, area: area)
        }
        let lessons = [
            lesson("Commutative Law", "Math"), lesson("Parts of Speech", "Language"),
            lesson("Parts of a Flower", "Botany")
        ]
        func give(_ index: Int, at date: Date, _ children: [UUID]) -> CDLessonAssignment {
            let assignment = planned(at: date, children: children, in: kids.context)
            if let id = lessons[index].id { assignment.lessonID = id.uuidString }
            return assignment
        }
        let day = [
            give(0, at: at(9, 45), [kids.lucy]),
            give(1, at: at(10, 0), [kids.ora, kids.naomi]),
            give(2, at: slot(0, .afternoon), [kids.naomi])
        ]
        try kids.context.save()

        let widths: [(String, CGFloat)] = [
            ("ipad", WeekPlanSection.columnWidth(forStripWidth: 900, dayCount: WeekPlanSection.visibleDayCount)),
            ("iphone", WeekPlanSection.minimumColumnWidth)
        ]
        for (device, width) in widths {
            let col = column(for: day, students: kids.students, away: realMonday(kids), width: width)
            #expect(col.awayNote(for: day[0], names: col.awayNames)?.isClash == true)
            #expect(col.awayNote(for: day[1], names: col.awayNames) == nil)
            #expect(col.awayNote(for: day[2], names: col.awayNames)?.isClash == false)
            for scheme in [ColorScheme.dark, .light] {
                let list = column(
                    for: day, students: kids.students, away: realMonday(kids), lessons: lessons, width: width
                ).dayList
                    .padding(WeekDayColumn.zonePadding)
                    .environment(\.managedObjectContext, kids.context)
                let png = try LessonTimePictures.save(
                    list,
                    named: "away-cards-\(device)", scheme: scheme, width: width
                )
                #expect((png?.count ?? 0) > 1_000)
            }
        }
    }
}
