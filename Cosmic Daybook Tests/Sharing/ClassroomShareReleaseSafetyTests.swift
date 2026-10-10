import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-10-05 sync and sharing hunt's Remove Last Year fixes: the plan checked again just
// before the run, one run at a time, unconfirmed deletes kept, the counts, and the stops.

extension ClassroomShareReleaseTests {

    /// A day counted from the fixture's school-year start (August 25, 2026).
    private func schoolDay(_ offset: Int) -> Date {
        let start = AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 8, day: 25)) ?? .distantPast
        )
        return AppCalendar.shared.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private func preview(
        _ fix: Fixture, scope: ClassroomShareScope
    ) async throws -> ClassroomShareRelease.Preview {
        let rows = try await ClassroomShareRelease.rows(
            container: fix.stack.container, storeID: fix.storeID, pinnedZone: Self.shareZone,
            scope: scope, environment: fix.cloud.environment()
        )
        return await ClassroomShareRelease.preview(rows, cutoff: scope.cutoff, container: fix.stack.container)
    }

    @discardableResult
    private func sharedMark(
        _ fix: Fixture, studentID: String, on date: Date?
    ) throws -> CDAttendanceRecord {
        let record = CDAttendanceRecord(context: fix.stack.viewContext)
        record.studentID = studentID
        record.date = date
        record.status = .present
        // Shared by its lasting ID: the one it has before a save goes with the save.
        try fix.stack.viewContext.obtainPermanentIDs(for: [record])
        fix.cloud.share([record.objectID])
        return record
    }

    // MARK: - The plan, checked again before the run

    @Test("A start date changed since the preview refuses the run; so do records the preview didn't hold")
    func changedPlanRefuses() async throws {
        let fix = try fixture()
        let confirmed = try await preview(fix, scope: ClassroomShareScope(cutoff: schoolDay(0)))
        #expect(ClassroomShareRelease.changeSincePreview(confirmed, confirmed: confirmed) == nil)

        // The start moved a week later while the sheet was open: this year's first mark
        // (day 6) would leave the share.
        let later = try await preview(fix, scope: ClassroomShareScope(cutoff: schoolDay(7)))
        #expect(later.records.contains(fix.currentNew.objectID))
        #expect(ClassroomShareRelease.changeSincePreview(later, confirmed: confirmed) != nil)
        // The start-date check runs on that start too: the day-6 mark is just before it.
        let ctx = fix.stack.viewContext
        #expect(ClassroomShareRelease.cutoffBlocker(later.cutoff, context: ctx, store: nil) != nil)
        #expect(ClassroomShareRelease.cutoffBlocker(confirmed.cutoff, context: ctx, store: nil) == nil)

        // Another of last year's marks reached the share after the preview: refused.
        let currentID = try #require(fix.current.id?.uuidString)
        let extra = try sharedMark(fix, studentID: currentID, on: schoolDay(-150))
        #expect(CoreDataTestHelpers.save(ctx))
        let grown = try await preview(fix, scope: ClassroomShareScope(cutoff: schoolDay(0)))
        #expect(grown.records.contains(extra.objectID))
        #expect(ClassroomShareRelease.changeSincePreview(grown, confirmed: confirmed) != nil)
        // Fewer than the preview held is no reason to stop.
        #expect(ClassroomShareRelease.changeSincePreview(confirmed, confirmed: grown) == nil)
    }

    @Test("A second run in the same app is refused while one runs")
    func secondRunRefused() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(!ClassroomShareRelease.isRunning)
        #expect(ClassroomShareRelease.claimRun())
        #expect(!ClassroomShareRelease.claimRun())
        #expect(ClassroomShareRelease.isRunning)
        #expect(
            ClassroomShareRelease.blocker(coreDataStack: stack, isRestoring: false)
                == ClassroomShareRelease.runningMessage
        )
        ClassroomShareRelease.endRun()
        #expect(!ClassroomShareRelease.isRunning)
        #expect(
            ClassroomShareRelease.blocker(coreDataStack: stack, isRestoring: false)
                != ClassroomShareRelease.runningMessage
        )
    }

    // MARK: - Deletes awaiting iCloud

    @Test("A stopped run's unconfirmed deletes stay on the list beside the next run's, and that run confirms them")
    func awaitingGoneAccumulates() async throws {
        let fix = try fixture()
        let cloud = fix.cloud
        // The first run stops between the departed child's deletes and iCloud's confirmation.
        let first = try await release(fix, cloud.environment { step, batch in
            if step == .originalsDeleted, batch.studentKey != nil { cloud.stop = "Quit partway" }
        })
        #expect(first.batchesDone == 0)
        let stranded = Set(cloud.awaiting.map(\.recordName))
        #expect(stranded.count == 4)
        cloud.stop = nil

        // The next run has one batch left (the older marks); its deletes join the list.
        let second = try await release(fix, cloud.environment { step, _ in
            guard step == .originalsDeleted else { return }
            let names = Set(cloud.awaiting.map(\.recordName))
            #expect(names.isSuperset(of: stranded))
            #expect(names.count == stranded.count + 2)
        })
        #expect(second.stoppedBecause == nil)
        #expect(second.batchesDone == 1)
        #expect(cloud.awaiting.isEmpty) // its own, then the stopped run's, both confirmed
    }

    @Test("A batch whose delete is refused takes only its own records off the list")
    func failedDeleteKeepsOthersOnList() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let stranded = CKRecord.ID(
            recordName: "stopped-run-original",
            zoneID: CKRecordZone.ID(zoneName: Self.shareZone, ownerName: CKCurrentUserDefaultName)
        )
        fix.cloud.awaiting = [stranded]
        // Another device deletes the departed child's private copy just before the delete.
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesChecked, batch.studentKey != nil else { return }
            let move = batch.moves[0]
            let context = container.newBackgroundContext()
            await context.perform {
                let source = try? context.existingObject(with: move.source)
                let request = NSFetchRequest<NSManagedObject>(entityName: move.entity)
                for object in (try? context.fetch(request)) ?? [] where object.objectID != move.source {
                    if object.value(forKey: "id") as? UUID == source?.value(forKey: "id") as? UUID {
                        context.delete(object)
                    }
                }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == ClassroomShareRelease.RunError.copyVanished.errorDescription)
        #expect(fix.cloud.awaiting == [stranded])
    }

    @Test("Finishing a stopped run nudges an export when iCloud still has the records and none starts")
    func finishNudgesExport() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        // A record of the notebook in no share (a copy an earlier batch left), for the nudge.
        let copy = CDAttendanceRecord(context: ctx)
        copy.studentID = try #require(fix.departed.id?.uuidString)
        copy.date = schoolDay(-200)
        copy.modifiedAt = schoolDay(-200)
        #expect(CoreDataTestHelpers.save(ctx))
        let records = await fix.cloud.environment().recordIDs(fix.departedMarks.map(\.objectID))
        fix.cloud.awaiting = Array(records.values) // the deletes never reached iCloud
        fix.cloud.exportStartAnswers = [false]

        let env = fix.cloud.environment(patience: .milliseconds(300)) // gives up on purpose
        let report = await ClassroomShareRelease.finishStopped(
            container: fix.stack.container, storeID: fix.storeID, environment: env
        )
        #expect(report.stoppedBecause != nil)
        #expect(fix.cloud.awaiting.count == 3)
        #expect(fix.cloud.exportStartQuestions == 2) // asked, nudged, asked again
        ctx.refresh(copy, mergeChanges: false)
        #expect((copy.modifiedAt ?? .distantPast) > schoolDay(-200))
    }

    // MARK: - The counts

    @Test("A mark another device deleted during the run is counted apart from the moved ones")
    func deletedElsewhereCountedApart() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let gone = fix.departedMarks[1].objectID
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesConfirmed, batch.studentKey != nil else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                if let object = try? context.existingObject(with: gone) { context.delete(object) }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        #expect(report.studentsMoved == 1)
        #expect(report.attendanceMoved == 4)
        #expect(report.deletedElsewhere == 1)
        #expect(ClassroomReleaseSheet.deletedElsewhereLine(report)?.hasPrefix("1 item was deleted") == true)
    }

    @Test("The preview tells older marks of children in class from others', and names what a backup can't hold")
    func previewCounts() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        // A child who left two years ago, whose record is already out of the share, and a
        // mark of hers still in it; a mark whose child is gone from the notebook.
        let earlier = CDStudent(context: ctx)
        earlier.firstName = "Iris"
        earlier.lastName = "Fern"
        earlier.enrollmentStatus = .withdrawn
        earlier.dateWithdrawn = schoolDay(-400)
        try sharedMark(fix, studentID: #require(earlier.id?.uuidString), on: schoolDay(-410))
        try sharedMark(fix, studentID: UUID().uuidString, on: schoolDay(-50))
        // Two a backup can't hold: no date, and a child id that isn't one.
        let undated = try sharedMark(fix, studentID: #require(fix.current.id?.uuidString), on: nil)
        let unlinked = try sharedMark(fix, studentID: "not an id", on: schoolDay(-40))
        #expect(CoreDataTestHelpers.save(ctx))

        let shown = try await preview(fix, scope: ClassroomShareScope(cutoff: schoolDay(0)))
        #expect(shown.children.map(\.name) == [fix.departed.fullName])
        #expect(shown.olderAttendance == 2) // the current child's
        #expect(shown.olderAttendanceOfChildrenWhoLeft == 2)
        #expect(!shown.records.contains(undated.objectID))
        #expect(!shown.records.contains(unlinked.objectID))
        let left = Dictionary(uniqueKeysWithValues: shown.leftShared.map { ($0.id, $0) })
        #expect(left.count == 2)
        let undatedLine = try #require(left[undated.objectID])
        #expect(undatedLine.gap == .noDate)
        #expect(ClassroomReleaseSheet.leftSharedLine(undatedLine) == "A mark for \(fix.current.fullName) with no date")
        #expect(left[unlinked.objectID]?.gap == .noChild)
        #expect(ClassroomReleaseSheet.olderLine(1, children: "children in this year's class")
            == "1 attendance mark from before that day, for children in this year's class, stops being shared too.")
    }

    // MARK: - Stops

    @Test("Another copy of the app opening the notebook stops the run before anything is touched")
    func anotherCopyStops() async throws {
        let fix = try fixture()
        var env = fix.cloud.environment()
        env.anotherCopyOpen = { true }
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause == ClassroomShareRelease.RunError.anotherCopyOpen.errorDescription)
        #expect(count("Student", in: fix) == 2)
    }

    @Test("While iCloud's account holds filing, removing last year is refused, saying why")
    func refusedUnderTheHolds() {
        let sync = CloudKitSyncStatusService()
        sync.accountNotReadyStores = ["private-store": .awaitingSetup]
        #expect(ClassroomShareRelease.syncBlocker(sync: sync) == "iCloud isn't ready yet. Try again in a few minutes.")
        sync.shareFilingPausedUntilReopen = true
        #expect(ClassroomShareRelease.syncBlocker(sync: sync)
            == "iCloud wasn't ready when the notebook opened. Quit and reopen it, then try again.")
        // It comes before a dead delegate's message: reopening is the fix either way.
        sync.markMirroringStopped(by: .notebook)
        #expect(ClassroomShareRelease.syncBlocker(sync: sync)
            == "iCloud wasn't ready when the notebook opened. Quit and reopen it, then try again.")

        let stopped = CloudKitSyncStatusService()
        stopped.markMirroringStopped(by: .notebook)
        #expect(ClassroomShareRelease.syncBlocker(sync: stopped)
            == "iCloud sync has stopped on this Mac. Quit and reopen the app, then try again.")
    }

    @Test("A Core Data error that stops a run reads as a change here, not as being offline")
    func coreDataErrorWording() {
        let raw = NSError(domain: NSCocoaErrorDomain, code: NSManagedObjectMergeError)
        let stop = ClassroomShareRelease.stopMessage(for: raw)
        #expect(stop.message == "Something changed while this ran, so it stopped. Nothing is lost. Run it again.")
        #expect(stop.details.contains("\(NSCocoaErrorDomain) \(NSManagedObjectMergeError)"))
    }
}
