import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-11-03, the work page's check-ins (#35, #37, #45, #46): a
/// check-in's Delete, Schedule New Check-In, and the Practice Overview's
/// check-in count.
@Suite("Work page check-ins (fix 11-03 W1)")
@MainActor
struct WorkPageCheckInsFix1103W1Tests {

    // MARK: - A check-in's Delete (#35)

    @Test("Deleting a check-in that carries a note keeps the note; the check-in is marked skipped")
    func checkInDeleteKeepsItsNote() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let checkIn = CDWorkCheckIn.make(
            for: mine, on: try CoreDataTestHelpers.day("2026-11-05"), purpose: "progressCheck", in: fixture.context
        )
        checkIn.setLegacyNoteText("Bring the bead frame", in: fixture.context)
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.deleteCheckIn(checkIn, modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(fixture.liveNotes == ["Bring the bead frame"])
        #expect(checkIn.managedObjectContext != nil)
        #expect(checkIn.status == .skipped)
        #expect(!fixture.context.hasChanges)
    }

    @Test("Deleting a check-in with no note takes it off, and the due date follows what is left")
    func checkInDeleteWithoutNoteRemovesIt() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let thursday = try CoreDataTestHelpers.day("2026-11-05")
        let monday = try CoreDataTestHelpers.day("2026-11-09")
        let first = CDWorkCheckIn.make(for: mine, on: thursday, purpose: "progressCheck", in: fixture.context)
        CDWorkCheckIn.make(for: mine, on: monday, purpose: "progressCheck", in: fixture.context)
        mine.dueAt = thursday
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.deleteCheckIn(first, modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(WorkLogService.checkIns(of: mine, in: fixture.context).compactMap(\.date) == [monday])
        #expect(mine.dueAt == monday)
        #expect(!fixture.context.hasChanges)
    }

    // MARK: - Schedule New Check-In (#37, #45)

    @Test("Closed work gets no check-in from the page")
    func closedWorkGetsNoCheckIn() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        mine.status = .mastered
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.newPlanDate = try CoreDataTestHelpers.day("2026-11-05")
        page.addCheckIn(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(WorkLogService.checkIns(of: mine, in: fixture.context).isEmpty)
    }

    @Test("A check-in picked for Saturday afternoon lands at the start of Monday")
    func checkInLandsOnStartOfNextSchoolDay() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let page = try fixture.page(for: mine)

        let saturday = try CoreDataTestHelpers.day("2026-11-07")
        page.newPlanDate = saturday.addingTimeInterval(14.5 * 3600)
        page.addCheckIn(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        let dates = WorkLogService.checkIns(of: mine, in: fixture.context).compactMap(\.date)
        #expect(dates == [try CoreDataTestHelpers.day("2026-11-09")])
        #expect(!fixture.context.hasChanges)
    }

    @Test("A second check-in on a day that already has one isn't added")
    func noSecondCheckInOnATakenDay() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let thursday = try CoreDataTestHelpers.day("2026-11-05")
        CDWorkCheckIn.make(for: mine, on: thursday, purpose: "progressCheck", in: fixture.context)
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        page.newPlanDate = thursday.addingTimeInterval(10 * 3600)
        page.newPlanNote = "Check the carrying"
        page.addCheckIn(modelContext: fixture.context, saveCoordinator: fixture.saveCoordinator)

        #expect(WorkLogService.checkIns(of: mine, in: fixture.context).count == 1)
        #expect(page.newPlanNote == "Check the carrying", "kept, so she can pick another day")
    }

    // MARK: - Practice Overview (#46)

    @Test("Practice Overview counts the work's scheduled check-ins, not dates written on sessions")
    func practiceOverviewCountsRealCheckIns() throws {
        let fixture = try Fix1103W1WorkPage.make()
        let mine = fixture.work(for: fixture.maya)
        let session = CDPracticeSession(context: fixture.context)
        session.checkInScheduledFor = AppCalendar.addingDays(2, to: Date())
        #expect(CoreDataTestHelpers.save(fixture.context))
        let page = try fixture.page(for: mine)

        #expect(page.practiceStats(sessions: [session]).upcomingCheckIns == 0, "no real check-in was made")

        let soon = AppCalendar.addingDays(3, to: AppCalendar.startOfDay(Date()))
        CDWorkCheckIn.make(for: mine, on: soon, in: fixture.context)
        CDWorkCheckIn.make(
            for: mine, on: AppCalendar.addingDays(-2, to: soon), status: .completed, in: fixture.context
        )
        CDWorkCheckIn.make(for: mine, on: AppCalendar.addingDays(1, to: soon), status: .skipped, in: fixture.context)
        #expect(CoreDataTestHelpers.save(fixture.context))

        #expect(page.practiceStats(sessions: [session]).upcomingCheckIns == 1)
    }
}
