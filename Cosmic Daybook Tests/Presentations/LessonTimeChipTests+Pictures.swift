import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// `LessonTimeChipTests`' pictures of a day's list, and the fixture both share.
/// `dayList` is drawn rather than the column: the column's body is a
/// `ScrollView`, which `ImageRenderer` draws blank.
extension LessonTimeChipTests {

    // MARK: - Pictures

    @Test("Pictures: a day with timed, untimed and clashing cards, at iPad and iPhone width")
    func pictures() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let children = ["Ora", "Avital", "Leshem", "Maya"].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Peretz")
        }
        let ids = try children.map { try #require($0.id) }
        func lesson(_ name: String, _ area: String) -> CDLesson {
            CoreDataTestHelpers.seedLesson(in: context, name: name, area: area)
        }
        let day = [
            planned(at: at(9, 30), lesson: lesson("Commutative Law", "Math"), children: [ids[0], ids[1]], in: context),
            planned(at: at(9, 30), lesson: lesson("Parts of Speech", "Language"), children: [ids[2]], in: context),
            planned(
                at: slot(0, .morning), lesson: lesson("Golden Bead Addition", "Math"), children: [ids[3]], in: context
            ),
            planned(
                at: at(13, 15), lesson: lesson("Parts of a Flower", "Botany"), children: [ids[1], ids[2]], in: context
            ),
            planned(
                at: slot(0, .afternoon), lesson: lesson("Timeline of Life", "History"), children: [ids[0]], in: context
            )
        ]
        try context.save()
        let ordered = LessonAssignmentOrdering.sorted(day, using: calendar)
        let lessons = context.safeFetch(CDFetchRequest(CDLesson.self))

        let widths: [(String, CGFloat)] = [
            ("ipad", WeekPlanSection.columnWidth(forStripWidth: 900, dayCount: 5)),
            ("iphone", WeekPlanSection.minimumColumnWidth)
        ]
        for (device, width) in widths {
            for scheme in [ColorScheme.dark, .light] {
                let column = column(for: ordered, lessons: lessons, students: children, width: width)
                let list = column.dayList
                    .padding(WeekDayColumn.zonePadding)
                    .environment(\.managedObjectContext, context)
                let png = try LessonTimePictures.save(
                    list, named: "day-list-\(device)", scheme: scheme, width: width
                )
                #expect((png?.count ?? 0) > 1_000)
            }
        }
    }

    // MARK: - Fixture

    func planned(
        at date: Date,
        lesson: CDLesson? = nil,
        children: [UUID] = [],
        in context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        let assignment = CDLessonAssignment(context: context)
        assignment.id = UUID()
        assignment.createdAt = wednesday
        if let lessonID = lesson?.id { assignment.lessonID = lessonID.uuidString }
        assignment.studentIDs = children.map(\.uuidString)
        assignment.schedule(for: date)
        return assignment
    }

    func column(
        for day: [CDLessonAssignment],
        lessons: [CDLesson] = [],
        students: [CDStudent] = [],
        width: CGFloat = WeekPlanSection.minimumColumnWidth
    ) -> WeekDayColumn {
        WeekDayColumn(
            day: wednesday,
            allLessonAssignments: day,
            scheduledLessons: day,
            lessons: lessons,
            students: students,
            visibleKinds: .everything,
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
            columnWidth: width
        )
    }
}
