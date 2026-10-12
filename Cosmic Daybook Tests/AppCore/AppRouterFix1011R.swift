import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, agent R: router requests that no screen answered
/// (#1–#4), the floating button's saved offset (#7) and the template
/// editors' sort order (#9).
@Suite("App core and navigation fixes 2026-10-11")
@MainActor
struct AppRouterFix1011R {
    typealias NavigationItem = RootView.NavigationItem
    typealias Restorer = RootView.NavigationSelectionRestorer

    // MARK: - #1 New Lesson

    @Test("New Lesson opens Lessons and carries its default area and sequence to the sheet, once")
    func newLessonNavigatesAndCarriesDefaults() {
        let router = AppRouter()
        router.requestNewLesson(defaultArea: "Math", defaultSequence: "Fractions")

        #expect(router.selectedNavItem == .lessons)
        let request = router.consumeNewLessonRequest()
        #expect(request == AppRouter.NewLessonRequest(defaultArea: "Math", defaultSequence: "Fractions"))
        #expect(router.navigationDestination == nil)
        #expect(router.consumeNewLessonRequest() == nil)
    }

    @Test("Consuming a New Lesson request leaves another screen's request alone")
    func newLessonConsumeIgnoresOtherRequests() {
        let router = AppRouter()
        let studentID = UUID()
        router.navigationDestination = .openStudentDetail(studentID)

        #expect(router.consumeNewLessonRequest() == nil)
        #expect(router.navigationDestination == .openStudentDetail(studentID))
    }

    // MARK: - #2 Open Student

    @Test("Open Student also selects Students off the Mac, so the request is acted on now")
    func openStudentSelectsStudents() {
        let router = AppRouter()
        let studentID = UUID()
        router.requestOpenStudentDetail(studentID)

        #expect(router.navigationDestination == .openStudentDetail(studentID))
        #if os(macOS)
        // The Mac opens the child in her own window instead.
        #expect(router.selectedNavItem == nil)
        #else
        #expect(router.selectedNavItem == .students)
        #endif
    }

    // MARK: - #3 New Student / Import Students

    @Test("New Student and Import Students go to Students as well as asking for their sheet")
    func studentRequestsNavigate() {
        let router = AppRouter()
        router.requestNewStudent()
        #expect(router.selectedNavItem == .students)
        #expect(router.navigationDestination == .newStudent)

        let other = AppRouter()
        other.requestImportStudents()
        #expect(other.selectedNavItem == .students)
        #expect(other.navigationDestination == .importStudents)
    }

    // MARK: - #4 Requests made while the app is still opening

    @Test("A section asked for before the window existed wins over the saved one, and the saved one isn't read")
    func pendingSelectionWinsOverSaved() {
        var savedWasRead = false
        let resolution = Restorer.launchSelection(pending: .attendance) {
            savedWasRead = true
            return RootView.NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .toSchedule)
        }
        #expect(resolution == RootView.NavigationSelectionResolution(item: .attendance))
        // Reading the saved selection can queue a Lessons & Work lens, which
        // would overwrite a request the pending section brought with it.
        #expect(!savedWasRead)
    }

    @Test("With nothing pending, the saved section is restored as before")
    func savedSelectionWithoutPending() {
        let saved = RootView.NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .attention)
        #expect(Restorer.launchSelection(pending: nil) { saved } == saved)
    }

    @Test("A pending aliased section lands on what it shows")
    func pendingAliasIsCanonical() {
        let resolution = Restorer.launchSelection(pending: .orders) {
            RootView.NavigationSelectionResolution(item: .today)
        }
        #expect(resolution.item == .supplies)
    }

    @Test("The router hands over a pending section once, so the same request later switches again")
    func routerHandsOverPendingSectionOnce() {
        let router = AppRouter()
        router.navigateTo(.attendance)

        #expect(router.takePendingNavItem() == .attendance)
        #expect(router.selectedNavItem == nil)
        #expect(router.takePendingNavItem() == nil)
    }

    @Test("A pending sheet request with no section names the section that answers it")
    func pendingDestinationImpliesSection() {
        let router = AppRouter()
        router.navigationDestination = .newStudent
        #expect(router.takePendingNavItem() == .students)
        // The sheet request itself stays for Students to answer.
        #expect(router.navigationDestination == .newStudent)

        let lessons = AppRouter()
        lessons.navigationDestination = .newLesson(defaultArea: nil, defaultSequence: nil)
        #expect(lessons.takePendingNavItem() == .lessons)
    }

    // MARK: - #7 The floating button's offset

    @Test("A saved offset that would put the button off-screen is pulled back into the window")
    func offsetIsClampedToContainer() {
        let container = CGSize(width: 400, height: 800)
        let clamped = QuickNoteGlassButton.clampedOffset(
            CGSize(width: -2_000, height: -3_000), in: container,
            buttonSize: 56, trailingInset: 16, bottomInset: 24
        )
        // Fully inside: the button's leading and top edges stay on screen.
        #expect(clamped.width >= -(container.width - 56 - 16))
        #expect(clamped.height >= -(container.height - 56 - 24))
        #expect(clamped.width < 0 && clamped.height < 0)

        let pushedOut = QuickNoteGlassButton.clampedOffset(
            CGSize(width: 500, height: 500), in: container,
            buttonSize: 56, trailingInset: 16, bottomInset: 24
        )
        #expect(pushedOut.width <= 16)
        #expect(pushedOut.height <= 24)
    }

    @Test("An offset already on screen is kept as it is")
    func offsetOnScreenUnchanged() {
        let offset = CGSize(width: -120, height: -300)
        #expect(QuickNoteGlassButton.clampedOffset(
            offset, in: CGSize(width: 400, height: 800),
            buttonSize: 56, trailingInset: 16, bottomInset: 24
        ) == offset)
    }

    // MARK: - #9 Template sort order

    @Test("A new custom template goes after the last one, even after a deletion left a gap")
    func templateSortOrderAfterDeletion() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for order in [Int64(0), 1] {
            let builtIn = CDNoteTemplate(context: context)
            builtIn.isBuiltIn = true
            builtIn.sortOrder = order
        }
        // Custom templates 100, 101 and 102, then 101 deleted.
        for order in [Int64(100), 102] {
            let custom = CDNoteTemplate(context: context)
            custom.isBuiltIn = false
            custom.sortOrder = order
        }
        #expect(TemplateSortOrder.nextCustom(for: CDNoteTemplate.self, in: context) == 103)
    }

    @Test("The first custom template starts at 100")
    func templateSortOrderFirstCustom() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let builtIn = CDMeetingTemplate(context: context)
        builtIn.isBuiltIn = true
        builtIn.sortOrder = 3
        #expect(TemplateSortOrder.nextCustom(for: CDMeetingTemplate.self, in: context) == 100)
    }
}
