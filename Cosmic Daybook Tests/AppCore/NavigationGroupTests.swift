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

    @Test("Groups keep the brief's order and only Library starts collapsed")
    func groupOrderAndDefaults() {
        #expect(
            NavigationGroup.all.map(\.id)
                == [.today, .children, .lessonsAndWork, .planning, .records, .library, .system]
        )
        #expect(NavigationGroup.all.filter { !$0.isExpandedByDefault }.map(\.id) == [.library])
        #expect(NavigationGroup.primaryTabs == [.today, .students, .attendance, .planningAgenda])
    }

    // MARK: - Raw values are frozen

    @Test("Every raw value is byte-identical to what saved scenes hold")
    func rawValuesArePinned() {
        #expect(NavigationItem.allCases.count == 33)
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
            ("garbage", .today, nil)
        ]
    )
    func savedNavItemResolves(raw: String, item: NavigationItem, scope: TriageBucket?) {
        let resolution = Restorer.resolve(navItemRaw: raw, legacyTabRaw: nil, planningModeRaw: nil)
        #expect(resolution == .init(item: item, lessonsAndWorkScope: scope))
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
            Restorer.resolve(navItemRaw: nil, legacyTabRaw: "nonsense", planningModeRaw: nil)
                == .init(item: .today)
        )
        #expect(Restorer.resolve(navItemRaw: nil, legacyTabRaw: nil, planningModeRaw: nil) == .init(item: .today))
    }

    // MARK: - Router

    @Test("The router can open the new Notes destination")
    func routerNavigatesToNotes() {
        let router = AppRouter()
        router.navigateTo(.notes)
        #expect(router.selectedNavItem == .notes)
    }
}
