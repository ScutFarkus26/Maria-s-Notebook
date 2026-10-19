import Foundation
import Testing
@testable import CosmicDaybook

/// `RootView.NavigationGroup` is the one table the macOS sidebar, the iPad
/// sidebar, and the iPhone tab bar plus More list all read. These lock down
/// what a careless edit to it would silently break: a destination nobody can
/// reach, one listed twice, a raw value renamed under a saved selection, and
/// the migrations that keep an old scene landing where it expects.
@Suite("Navigation groups")
@MainActor
struct NavigationGroupTests {
    typealias NavigationItem = RootView.NavigationItem
    typealias NavigationGroup = RootView.NavigationGroup
    typealias Restorer = RootView.NavigationSelectionRestorer

    private var destinations: Set<NavigationItem> {
        Set(NavigationItem.allCases).subtracting(NavigationItem.aliases.keys)
    }

    // MARK: - Every destination has exactly one home

    @Test("Every destination sits in exactly one group")
    func everyDestinationInExactlyOneGroup() {
        let listed = NavigationGroup.all.flatMap(\.items)
        #expect(Set(listed) == destinations)
        #expect(listed.count == Set(listed).count, "a destination is listed in two groups")
    }

    @Test("Aliases resolve into a group, idempotently, and never onto another alias")
    func aliasesResolveIntoGroups() {
        for (alias, target) in NavigationItem.aliases {
            #expect(NavigationItem.aliases[target] == nil, "\(alias) points at another alias")
            #expect(alias.canonical == target)
            #expect(target.canonical == target)
            #expect(NavigationGroup.containing(alias)?.items.contains(target) == true)
        }
        for item in destinations {
            #expect(item.canonical == item)
        }
    }

    // MARK: - The iOS TabView lists everything once

    @Test("The iPhone tab bar plus its sections list every destination once")
    func tabViewListsEveryDestinationOnce() {
        let tabs = NavigationGroup.primaryTabs + NavigationGroup.secondaryGroups.flatMap(\.secondaryItems)
        #expect(Set(tabs) == destinations)
        #expect(tabs.count == destinations.count, "a Tab value appears twice")
        for item in NavigationGroup.primaryTabs {
            #expect(NavigationGroup.containing(item) != nil, "\(item) is in the bar but in no group")
        }
    }

    // MARK: - Group shape

    @Test("Six groups in order, 21 rows, and only Classroom starts collapsed")
    func groupOrderAndDefaults() {
        #expect(NavigationGroup.all.map(\.id) == [.today, .children, .planning, .classroom, .library, .system])
        #expect(NavigationGroup.all.map(\.title) == ["Today", "Children", "Plan", "Classroom", "Library", "System"])
        #expect(NavigationGroup.all.filter { !$0.isExpandedByDefault }.map(\.id) == [.classroom])
        #expect(NavigationGroup.all.flatMap(\.items).count == 21)
        #expect(NavigationGroup.primaryTabs == [.today, .students, .attendance, .planningAgenda])
        // The Plan group keeps the old Planning group's expansion key.
        #expect(RootView.NavigationGroupID.planning.rawValue == "planning")
    }

    @Test("Each group lists the rows the Simplify plan settled on, in order")
    func groupRows() {
        let rows = Dictionary(uniqueKeysWithValues: NavigationGroup.all.map { ($0.id, $0.items) })
        #expect(rows[.today] == [.today, .attendance, .todos])
        #expect(rows[.children] == [.students, .meetings, .notes, .parentReports])
        #expect(rows[.planning] == [.planningAgenda, .smallSequencePlanner, .planningChecklist,
                                    .planningCalendar, .thisWeeksParsha])
        #expect(rows[.classroom] == [.supplies, .community, .planningProjects, .goingOut, .schedules])
        #expect(rows[.library] == [.lessons, .teachingAlbums, .resourceLibrary])
        #expect(rows[.system] == [.settings])
    }

    @Test("The merged screens carry their new names")
    func mergedScreenNames() {
        #expect(NavigationItem.planningChecklist.displayName == "Class Grid")
        #expect(NavigationItem.resourceLibrary.displayName == "Resources")
        #expect(NavigationItem.planningProjects.displayName == "Clubs & Projects")
    }

    @Test("Settings sits at the bottom of the sidebar, in System")
    func settingsIsTheLastSidebarRow() {
        #expect(NavigationGroup.containing(.settings)?.id == .system)
        #expect(NavigationGroup.all.last?.items.last == .settings)
    }

    // MARK: - Raw values are frozen

    @Test("Every raw value is byte-identical to what saved scenes hold")
    func rawValuesArePinned() {
        #expect(NavigationItem.allCases.count == 34)
        #expect(NavigationItem.today.rawValue == "today")
        #expect(NavigationItem.attendance.rawValue == "attendance")
        #expect(NavigationItem.note.rawValue == "note")
        #expect(NavigationItem.students.rawValue == "students")
        #expect(NavigationItem.parentReports.rawValue == "parentReports")
        #expect(NavigationItem.supplies.rawValue == "supplies")
        #expect(NavigationItem.procedures.rawValue == "procedures")
        #expect(NavigationItem.meetings.rawValue == "meetings")
        #expect(NavigationItem.lessons.rawValue == "lessons")
        #expect(NavigationItem.teachingAlbums.rawValue == "teachingAlbums")
        #expect(NavigationItem.stories.rawValue == "stories")
        #expect(NavigationItem.bookClub.rawValue == "bookClub")
        #expect(NavigationItem.more.rawValue == "more")
        #expect(NavigationItem.todos.rawValue == "todos")
        #expect(NavigationItem.planningChecklist.rawValue == "planningChecklist")
        #expect(NavigationItem.planningAgenda.rawValue == "planningAgenda")
        #expect(NavigationItem.planningProjects.rawValue == "planningProjects")
        #expect(NavigationItem.planningCalendar.rawValue == "planningCalendar")
        #expect(NavigationItem.progressDashboard.rawValue == "progressDashboard")
        #expect(NavigationItem.curriculumMap.rawValue == "curriculumMap")
        #expect(NavigationItem.lessonRecall.rawValue == "lessonRecall")
        #expect(NavigationItem.goingOut.rawValue == "goingOut")
        #expect(NavigationItem.smallSequencePlanner.rawValue == "smallSequencePlanner")
        #expect(NavigationItem.perpetualCalendar.rawValue == "perpetualCalendar")
        #expect(NavigationItem.community.rawValue == "community")
        #expect(NavigationItem.schedules.rawValue == "schedules")
        #expect(NavigationItem.resourceLibrary.rawValue == "resourceLibrary")
        #expect(NavigationItem.askAI.rawValue == "askAI")
        #expect(NavigationItem.logs.rawValue == "logs")
        #expect(NavigationItem.notes.rawValue == "notes")
        #expect(NavigationItem.settings.rawValue == "settings")
        #expect(NavigationItem.thisWeeksParsha.rawValue == "thisWeeksParsha")
        #expect(NavigationItem.parshaCalendar.rawValue == "parshaCalendar")
        #expect(NavigationItem.orders.rawValue == "orders")
        #expect(Restorer.retiredOpenWorkNavItemRaw == "planningWork")
        #expect(Restorer.retiredNeedsLessonNavItemRaw == "needsLesson")
    }

    // MARK: - Selection restore

    @Test(
        "A saved navigation item lands on the destination it meant",
        arguments: [
            ("community", NavigationItem.community, TriageBucket?.none),
            ("planningWork", .planningAgenda, .attention),
            ("needsLesson", .planningAgenda, .toSchedule),
            ("perpetualCalendar", .planningCalendar, nil),
            ("more", .today, nil),
            ("note", .today, nil),
            ("notes", .notes, nil),
            ("orders", .supplies, nil),
            ("garbage", .today, nil)
        ]
    )
    func savedNavItemResolves(raw: String, item: NavigationItem, scope: TriageBucket?) {
        let resolution = Restorer.resolve(navItemRaw: raw, legacyTabRaw: nil, planningModeRaw: nil)
        #expect(resolution == .init(item: item, lessonsAndWorkScope: scope))
    }

    @Test(
        "A retired row restores to the screen that replaced it, on its view",
        arguments: [
            ("logs", NavigationItem.notes, ScreenLanding?.none),
            ("curriculumMap", .planningChecklist, .classGrid(.threeYears)),
            ("progressDashboard", .planningChecklist, .classGrid(.children)),
            ("lessonRecall", .planningChecklist, .classGrid(.recall)),
            ("planningChecklist", .planningChecklist, nil),
            ("parshaCalendar", .thisWeeksParsha, .parshaYearList),
            ("stories", .resourceLibrary, .resources(.stories)),
            ("procedures", .resourceLibrary, .resources(.procedures)),
            ("resourceLibrary", .resourceLibrary, nil),
            ("bookClub", .planningProjects, nil),
            ("askAI", .today, nil)
        ]
    )
    func retiredRowResolves(raw: String, item: NavigationItem, landing: ScreenLanding?) {
        let resolution = Restorer.resolve(navItemRaw: raw, legacyTabRaw: nil, planningModeRaw: nil)
        #expect(resolution == .init(item: item, landing: landing))
    }

    @Test("Every retired row lands on a visible tab on iPhone")
    func retiredRowsLandOnVisibleTabs() {
        let visible = Set(NavigationGroup.primaryTabs + NavigationGroup.secondaryGroups.flatMap(\.secondaryItems))
        for alias in NavigationItem.aliases.keys {
            #expect(visible.contains(alias.canonical), "\(alias) restores to a hidden tab")
        }
    }

    @Test("A router jump to a retired row opens its new screen on its view, once")
    func routerJumpToRetiredRowSetsLanding() {
        let router = AppRouter()
        router.navigateTo(.lessonRecall)
        #expect(router.selectedNavItem == .lessonRecall)
        #expect(router.takePendingNavItem() == .planningChecklist)
        #expect(router.screenLanding == .classGrid(.recall))
        // Resources doesn't take the Class Grid's landing.
        #expect(router.consumeScreenLanding { landing -> LibraryKind? in
            if case .resources(let kind) = landing { return kind }
            return nil
        } == nil)
        #expect(router.consumeScreenLanding { landing -> ClassGridViewKind? in
            if case .classGrid(let view) = landing { return view }
            return nil
        } == .recall)
        #expect(router.screenLanding == nil)

        router.navigateTo(.notes)
        #expect(router.screenLanding == nil)
    }

    @Test("A saved navigation item wins over the legacy tab; an unknown one falls through to it")
    func savedNavItemWinsOverLegacyTab() {
        #expect(
            Restorer.resolve(navItemRaw: "students", legacyTabRaw: "Community", planningModeRaw: "Open Work")
                == .init(item: .students)
        )
        #expect(
            Restorer.resolve(navItemRaw: "garbage", legacyTabRaw: "Community", planningModeRaw: nil)
                == .init(item: .community)
        )
    }

    @Test("A scene saved by the old Tab enum still opens the matching screen")
    func legacyTabResolves() {
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Community", planningModeRaw: nil)
                == .init(item: .community)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Planning", planningModeRaw: "Open Work")
                == .init(item: .planningAgenda, lessonsAndWorkScope: .attention)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Planning", planningModeRaw: nil)
                == .init(item: .planningAgenda)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Planning", planningModeRaw: "Projects")
                == .init(item: .planningProjects)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Planning", planningModeRaw: "Checklist")
                == .init(item: .planningChecklist)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Planning", planningModeRaw: "anything else")
                == .init(item: .planningAgenda, lessonsAndWorkScope: .toSchedule)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "Logs", planningModeRaw: nil)
                == .init(item: .notes)
        )
        #expect(
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "nonsense", planningModeRaw: nil)
                == .init(item: .today)
        )
        #expect(Restorer.resolve(navItemRaw: nil, legacyTabRaw: nil, planningModeRaw: nil) == .init(item: .today))
    }

    // MARK: - Restock

    @Test("Supplies shows as Restock, and Orders folds into it")
    func restockReplacesSuppliesAndOrders() {
        #expect(NavigationItem.supplies.displayName == "Restock")
        #expect(NavigationItem.supplies.icon == "shippingbox")
        #expect(NavigationItem.orders.canonical == .supplies)
        #expect(NavigationGroup.containing(.supplies)?.id == .classroom)
        #expect(NavigationGroup.all.flatMap(\.items).contains(.orders) == false)
    }

    // MARK: - Router

    @Test("The router can open the new Notes destination")
    func routerNavigatesToNotes() {
        let router = AppRouter()
        router.navigateTo(.notes)
        #expect(router.selectedNavItem == .notes)
    }
}
