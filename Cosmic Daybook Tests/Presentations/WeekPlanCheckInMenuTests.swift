#if os(iOS)
import CoreData
import SwiftUI
import Testing
import UIKit
@testable import CosmicDaybook

/// The week plan's check-in pill menu looks up the pill's rows only when the
/// menu is built for display.
///
/// `.contextMenu` calls its content closure on every pass of the pill's day
/// column, and the menu's status items used to be built there: every
/// check-in's work resolved twice (once for the rows, again for the named
/// children) and every child named, for every pill, on every column redraw.
/// They now live in `WorkCheckPillStatusMenu`'s body. These pin that drawing
/// a column runs no lookup, that drawing the status menu runs one, and that
/// the menu offers exactly the rows and children the eager lookup offered
/// (kept verbatim below).
@Suite("Week plan check-in menu")
@MainActor
struct WeekPlanCheckInMenuTests {

    // MARK: - The eager lookup, verbatim

    /// `WeekPlanSection.rows(of:)` before the change.
    private func oldRows(of group: CalendarCheckInGroup, in viewContext: NSManagedObjectContext) -> [CDWorkModel] {
        var seen: Set<NSManagedObjectID> = []
        return group.checkIns.compactMap { checkIn in
            guard let work = checkIn.resolvedWork(in: viewContext),
                  seen.insert(work.objectID).inserted else { return nil }
            return work
        }
    }

    /// `WeekPlanSection.children(of:)` before the change.
    private func oldChildren(
        of group: CalendarCheckInGroup,
        in viewContext: NSManagedObjectContext,
        checkInLookup: CalendarCheckInGrouper.Lookup
    ) -> [WorkLogStatusMenu.Child] {
        oldRows(of: group, in: viewContext).compactMap { work in
            guard let id = work.id else { return nil }
            let name = checkInLookup.studentName(for: work)
            return WorkLogStatusMenu.Child(id: id, name: name.isEmpty ? "Student" : name, work: work)
        }
    }

    // MARK: - Fixture

    private struct Day {
        let context: NSManagedObjectContext
        let date: Date
        let groups: [CalendarCheckInGroup]
        let lookup: CalendarCheckInGrouper.Lookup
    }

    /// Today's check-ins, as the strip groups them: one lesson's work for
    /// three children and a child no longer on file (Ora has two check-ins on
    /// her one row; Leshem's carries only the work's id string, written before
    /// the relationship was always set); another lesson's work for Ora alone;
    /// and an individual row for Avital.
    private func seedDay() throws -> Day {
        let context = try CoreDataTestHelpers.makeContext()
        let day = AppCalendar.startOfDay(Date())
        let laws = try #require(CoreDataTestHelpers.seedLesson(in: context, name: "Commutative Law").id)
        let squares = try #require(CoreDataTestHelpers.seedLesson(in: context, name: "Squaring").id)
        let children = try ["Ora", "Avital", "Leshem"].map {
            try #require(CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Peretz").id)
        }
        func work(_ student: UUID, _ lesson: UUID) -> CDWorkModel {
            CoreDataTestHelpers.seedWorkModel(in: context, title: "Practice", studentID: student, lessonID: lesson)
        }

        let ora = work(children[0], laws)
        CDWorkCheckIn.make(for: ora, on: day, purpose: "progressCheck", in: context)
        CDWorkCheckIn.make(for: ora, on: day, purpose: "progressCheck", in: context)
        CDWorkCheckIn.make(for: work(children[1], laws), on: day, purpose: "progressCheck", in: context)
        let leshem = CDWorkCheckIn(context: context)
        leshem.workID = work(children[2], laws).id?.uuidString ?? ""
        leshem.date = day
        leshem.purpose = "progressCheck"
        CDWorkCheckIn.make(for: work(UUID(), laws), on: day, purpose: "progressCheck", in: context)
        CDWorkCheckIn.make(for: work(children[0], squares), on: day, purpose: "progressCheck", in: context)
        let solo = work(children[1], laws)
        solo.checkInStyle = .individual
        CDWorkCheckIn.make(for: solo, on: day, purpose: "progressCheck", in: context)
        try context.save()

        let (start, end) = AppCalendar.dayRange(for: day)
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = CalendarCheckInGrouper.scheduledPredicate(start: start, end: end)
        let checkIns = context.safeFetch(request)
        let lookup = CalendarCheckInGrouper.Lookup.build(for: checkIns, in: context)
        return Day(
            context: context,
            date: day,
            groups: CalendarCheckInGrouper.groups(from: checkIns, lookup: lookup),
            lookup: lookup
        )
    }

    /// Counts the pill actions' lookups.
    private final class Lookups {
        var rows = 0
        var children = 0
    }

    /// The old shape, for contrast: the status items built inside the
    /// `.contextMenu` closure, which runs whenever the pill is drawn.
    private struct EagerPill: View {
        let group: CalendarCheckInGroup
        let actions: WorkCheckPillActions

        var body: some View {
            Text(group.lessonTitle)
                .contextMenu {
                    WorkLogStatusMenu(
                        targets: actions.rows(group),
                        children: actions.children(actions.rows(group))
                    ) { rows, status in
                        actions.log(group, rows, status)
                    }
                }
        }
    }

    private func actions(for day: Day, counting lookups: Lookups) -> WorkCheckPillActions {
        WorkCheckPillActions(
            rows: { group in
                lookups.rows += 1
                return WorkCheckPillActions.rows(of: group, in: day.context)
            },
            children: { rows in
                lookups.children += 1
                return WorkCheckPillActions.children(of: rows, lookup: day.lookup)
            },
            log: { _, _, _ in },
            openWork: { _ in }
        )
    }

    private func column(for day: Day, actions: WorkCheckPillActions) -> some View {
        WeekDayColumn(
            day: day.date,
            allLessonAssignments: [],
            scheduledLessons: [],
            lessons: [],
            students: [],
            visibleKinds: .everything,
            checkInGroups: day.groups,
            focusedPresentationID: nil,
            onClear: { _ in },
            onSelect: { _ in },
            onOpenCheckInGroup: { _ in },
            onDropWorkCheckIns: { _, _ in },
            onDropWork: { _, _ in },
            pillActions: actions
        )
        .environment(\.managedObjectContext, day.context)
    }

    // MARK: - Tests

    /// The menu against the eager lookup, item for item.
    private func expectSame(
        _ menu: WorkLogStatusMenu, rows: [CDWorkModel], children: [WorkLogStatusMenu.Child]
    ) {
        let targets: [NSManagedObjectID] = menu.targets.map { $0.objectID }
        let eagerTargets: [NSManagedObjectID] = rows.map { $0.objectID }
        #expect(targets == eagerTargets)
        let ids: [UUID] = menu.children.map { $0.id }
        let eagerIDs: [UUID] = children.map { $0.id }
        #expect(ids == eagerIDs)
        let names: [String] = menu.children.map { $0.name }
        let eagerNames: [String] = children.map { $0.name }
        #expect(names == eagerNames)
        let works: [NSManagedObjectID] = menu.children.map { $0.work.objectID }
        let eagerWorks: [NSManagedObjectID] = children.map { $0.work.objectID }
        #expect(works == eagerWorks)
    }

    @Test("The menu offers exactly the rows and children the eager lookup offered")
    func menuMatchesTheEagerLookup() throws {
        let day = try seedDay()
        let pillSizes: [Int] = day.groups.map { $0.checkIns.count }.sorted()
        #expect(pillSizes == [1, 1, 5])
        let actions = actions(for: day, counting: Lookups())

        for group in day.groups {
            let body = WorkCheckPillStatusMenu(group: group, actions: actions).body
            let menu = try #require(body as? WorkLogStatusMenu)
            expectSame(
                menu,
                rows: oldRows(of: group, in: day.context),
                children: oldChildren(of: group, in: day.context, checkInLookup: day.lookup)
            )
        }

        // The grouped pill: five check-ins on four rows (Ora's two share
        // hers), the departed child named "Student", Leshem found by id.
        let groupedPill = day.groups.first { $0.isGrouped }
        let grouped = try #require(groupedPill)
        let children = oldChildren(of: grouped, in: day.context, checkInLookup: day.lookup)
        let names: [String] = children.map { $0.name }.sorted()
        let expectedNames: [String] = ["Avital P", "Leshem P", "Ora P", "Student"]
        #expect(names == expectedNames)
    }

    @Test("Drawing a day column runs no menu lookup; drawing the status menu runs one")
    func columnDrawRunsNoLookup() async throws {
        let day = try seedDay()
        let columnLookups = Lookups()
        let menuLookups = Lookups()
        let eagerLookups = Lookups()
        let columnActions = actions(for: day, counting: columnLookups)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 700)
        let host = UIHostingController(rootView: AnyView(VStack {
            column(for: day, actions: columnActions)
            // The status items drawn in the open, as the column used to build
            // them on every pass.
            WorkCheckPillStatusMenu(group: day.groups[0], actions: actions(for: day, counting: menuLookups))
            EagerPill(group: day.groups[0], actions: actions(for: day, counting: eagerLookups))
        }))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        // All three draw in the same pass.
        let deadline = ContinuousClock.now + .seconds(10)
        while menuLookups.rows == 0 || eagerLookups.rows == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(menuLookups.rows == 1)
        #expect(menuLookups.children == 1)
        // A menu built in the closure looks up on a plain draw of its view...
        #expect(eagerLookups.rows >= 2)
        // ...and the column's pills, drawn in the same pass, looked up nothing.
        #expect(columnLookups.rows == 0)
        #expect(columnLookups.children == 0)

        // Redraws of the column alone, as the strip makes them, look nothing up.
        for _ in 0..<3 {
            host.rootView = AnyView(column(for: day, actions: columnActions))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(columnLookups.rows == 0)
        #expect(columnLookups.children == 0)
    }
}
#endif
