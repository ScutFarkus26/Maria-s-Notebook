import CloudKit
import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

// The 2026-11-02 sync, sharing and backup hunt's Remove Last Year findings (#36–#41, #53):
// a change made during the run, a child back before a stopped run was finished, the deletes
// awaiting iCloud, and the run's saves carrying the app's author.

extension ClassroomShareReleaseTests {

    /// A day counted from the fixture's school-year start (August 25, 2026).
    private func huntDay(_ offset: Int) -> Date {
        let start = AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 8, day: 25)) ?? .distantPast
        )
        return AppCalendar.shared.date(byAdding: .day, value: offset, to: start) ?? start
    }

    // MARK: - #37: a change made while the run goes

    @Test("A change to an original after its copy was checked, just before the delete, is carried over, not lost")
    func changeBeforeDeleteCarried() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let noted = fix.departedMarks[0].objectID
        let once = ReleaseTestOnce()
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesChecked, batch.studentKey != nil, once.claim() else { return }
            // The guide edits the mark on the Mac while the batch is between its check and its delete.
            let context = container.newBackgroundContext()
            await context.perform {
                let mark = try? context.existingObject(with: noted) as? CDAttendanceRecord
                mark?.note = "Changed during the run"
                mark?.modifiedAt = Date()
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        #expect(report.attendanceMoved == 5)
        let notes = fix.stack.viewContext.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).compactMap(\.note)
        #expect(notes.contains("Changed during the run"))
        #expect(count("AttendanceRecord", in: fix) == 6)
    }

    @Test("An original that keeps changing between check and delete stops the run with nothing deleted")
    func changingOriginalStops() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let student = fix.departed.objectID
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesChecked, batch.studentKey != nil else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                let child = try? context.existingObject(with: student) as? CDStudent
                child?.nickname = UUID().uuidString
                child?.modifiedAt = Date()
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause == ClassroomShareRelease.RunError.changedDuringRun.errorDescription)
        #expect(fix.cloud.exists(fix.departed.objectID))
        #expect(fix.departedMarks.allSatisfy { fix.cloud.exists($0.objectID) })
        #expect(fix.cloud.awaiting.isEmpty) // nothing was deleted, so nothing waits on iCloud
    }

    @Test("A nudge's millisecond on a copy is no change: the delete goes ahead")
    func nudgeIsNoChange() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let original = CDAttendanceRecord(context: ctx)
        original.studentID = UUID().uuidString
        original.date = Date()
        original.modifiedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let copy = NSManagedObject(entity: original.entity, insertInto: ctx)
        ClassroomShareRelease.copyAttributes(from: original, to: copy)
        copy.setValue(Date(timeIntervalSinceReferenceDate: 1_000.001), forKey: "modifiedAt")
        #expect(!ClassroomShareRelease.changedSinceCopied(original, copy))
        original.note = "Edited"
        #expect(ClassroomShareRelease.changedSinceCopied(original, copy))
        // A copy edited after the original keeps its own values: no change to carry.
        copy.setValue(Date(timeIntervalSinceReferenceDate: 5_000), forKey: "modifiedAt")
        #expect(!ClassroomShareRelease.changedSinceCopied(original, copy))
    }

    // MARK: - #38: a child back before a stopped run was finished

    /// The private copy a run that stopped after its third step left of `original`.
    private func stoppedRunsCopy(of original: NSManagedObject, in fix: Fixture) -> NSManagedObject {
        let ctx = fix.stack.viewContext
        let twin = NSManagedObject(entity: original.entity, insertInto: ctx)
        ClassroomShareRelease.copyAttributes(from: original, to: twin)
        return twin
    }

    private func students(withID id: UUID, in fix: Fixture) -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return fix.stack.viewContext.safeFetch(request)
    }

    @Test("A child back after a run stopped partway is left once: the private copy goes, the shared one stays")
    func returningChildTwinCleanedUp() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let id = try #require(fix.departed.id)
        fix.departed.modifiedAt = huntDay(-80)
        let twin = stoppedRunsCopy(of: fix.departed, in: fix)
        #expect(CoreDataTestHelpers.save(ctx))
        // She comes back, re-enrolled on the shared record.
        fix.departed.enrollmentStatus = .enrolled
        fix.departed.dateWithdrawn = nil
        fix.departed.modifiedAt = huntDay(10)
        #expect(CoreDataTestHelpers.save(ctx))

        let env = fix.cloud.environment()
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        #expect(students(withID: id, in: fix).count == 1)
        #expect(fix.cloud.exists(fix.departed.objectID)) // the shared one, which the assistants see
        #expect(!fix.cloud.exists(twin.objectID))
        #expect(fix.cloud.isShared(fix.departed.objectID))
        #expect(try await plan(fix, environment: env).isEmpty)
        #expect(report.twinsCleaned == 1)
        #expect(report.attendanceMoved == 5) // her old marks and the current child's
        ctx.refreshAllObjects()
        #expect(fix.departed.enrollmentStatus == .enrolled)
    }

    @Test("The plan for a child back after a stopped run: her private copy goes, last, in a batch of its own")
    func returningChildPlan() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let twin = stoppedRunsCopy(of: fix.departed, in: fix)
        fix.departed.enrollmentStatus = .enrolled
        fix.departed.dateWithdrawn = nil
        twin.setValue(CDStudent.EnrollmentStatus.enrolled.rawValue, forKey: "enrollmentStatusRaw")
        twin.setValue(nil, forKey: "dateWithdrawn")
        #expect(CoreDataTestHelpers.save(ctx))

        let batches = try await plan(fix, environment: fix.cloud.environment())
        let last = try #require(batches.last)
        #expect(last.moves.isEmpty)
        #expect(last.twinCleanups == [ClassroomShareRelease.TwinCleanup(
            entity: "Student", studentKey: ClassroomShareScope.normalizedID(fix.departed.id?.uuidString ?? ""),
            shared: fix.departed.objectID, twins: [twin.objectID]
        )])
        #expect(batches.dropLast().allSatisfy { $0.twinCleanups.isEmpty })
        // The backup must hold both copies, and the preview names it.
        let records = ClassroomShareRelease.records(in: batches)
        #expect(records.contains(twin.objectID) && records.contains(fix.departed.objectID))
        let shown = await ClassroomShareRelease.preview(
            try await ClassroomShareRelease.rows(
                container: fix.stack.container, storeID: fix.storeID, pinnedZone: Self.shareZone,
                scope: ClassroomShareScope(cutoff: huntDay(0)), environment: fix.cloud.environment()
            ),
            cutoff: huntDay(0), container: fix.stack.container
        )
        #expect(shown.heldTwice == 1)
        #expect(shown.children.isEmpty)
        #expect(ClassroomReleaseSheet.heldTwiceLine(1).hasPrefix("1 item a run that stopped partway left"))
    }

    @Test("A private copy edited after its shared original brings the edit over before it goes")
    func twinEditCarriedToShared() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let id = try #require(fix.departed.id)
        fix.departed.modifiedAt = huntDay(-80)
        let twin = stoppedRunsCopy(of: fix.departed, in: fix)
        #expect(CoreDataTestHelpers.save(ctx))
        // She comes back, re-enrolled on the private copy the roster showed.
        twin.setValue(CDStudent.EnrollmentStatus.enrolled.rawValue, forKey: "enrollmentStatusRaw")
        twin.setValue(nil, forKey: "dateWithdrawn")
        twin.setValue("Lee", forKey: "nickname")
        twin.setValue(huntDay(10), forKey: "modifiedAt")
        #expect(CoreDataTestHelpers.save(ctx))

        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        #expect(report.twinsCleaned == 1)
        ctx.refreshAllObjects()
        let left = students(withID: id, in: fix)
        #expect(left.map(\.objectID) == [fix.departed.objectID])
        #expect(left.first?.enrollmentStatus == .enrolled)
        #expect(left.first?.nickname == "Lee")
    }

    @Test("A private copy edited during the cleanup, before its delete, is checked again and its edit kept")
    func twinEditedDuringCleanup() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let container = fix.stack.container
        fix.departed.enrollmentStatus = .enrolled
        fix.departed.dateWithdrawn = nil
        fix.departed.modifiedAt = huntDay(10)
        let twin = stoppedRunsCopy(of: fix.departed, in: fix)
        #expect(CoreDataTestHelpers.save(ctx))
        let twinID = twin.objectID
        let once = ReleaseTestOnce()
        let env = fix.cloud.environment { step, _ in
            guard step == .twinsChecked, once.claim() else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                let copy = try? context.existingObject(with: twinID)
                copy?.setValue("Edited meanwhile", forKey: "nickname")
                copy?.setValue(Date(), forKey: "modifiedAt")
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        #expect(report.twinsCleaned == 1)
        #expect(!fix.cloud.exists(twinID))
        ctx.refreshAllObjects()
        #expect(fix.departed.nickname == "Edited meanwhile")
    }

    @Test("When the shared original leaves this Mac during a cleanup, its private copy is kept")
    func sharedGoneKeepsTwin() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let container = fix.stack.container
        fix.departed.enrollmentStatus = .enrolled
        fix.departed.dateWithdrawn = nil
        let twin = stoppedRunsCopy(of: fix.departed, in: fix)
        #expect(CoreDataTestHelpers.save(ctx))
        let shared = fix.departed.objectID
        let env = fix.cloud.environment { step, _ in
            guard step == .sharedConfirmed else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                if let object = try? context.existingObject(with: shared) { context.delete(object) }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        let gone = ClassroomShareRelease.RunError.sharedOriginalGone.errorDescription
        #expect(report.stoppedBecause == gone)
        #expect(fix.cloud.exists(twin.objectID))
        #expect(report.twinsCleaned == 0)
    }

    // MARK: - #41: deletes awaiting iCloud

    @Test("A stopped run's deletes whose records are back in the notebook are dropped, not waited on")
    func awaitingRecordsBackHereDropped() async throws {
        let fix = try fixture()
        // The list names records that are here again (re-downloaded) and belong this year.
        let records = await fix.cloud.environment().recordIDs([fix.current.objectID, fix.currentNew.objectID])
        fix.cloud.awaiting = Array(records.values)
        let report = await ClassroomShareRelease.finishStopped(
            stack: fix.stack, storeID: fix.storeID, environment: fix.cloud.environment()
        )
        #expect(report.stoppedBecause == nil)
        #expect(fix.cloud.awaiting.isEmpty)
        #expect(fix.cloud.exists(fix.current.objectID))
        #expect(report.unconfirmed == 0) // dropped, not waited on until the deadline
    }

    @Test("Deletes awaiting iCloud in a share zone that's gone count as gone, and the list clears")
    func awaitingInGoneZoneFinish() async throws {
        let fix = try fixture()
        let marks = fix.departedMarks.map(\.objectID)
        let records = await fix.cloud.environment().recordIDs(marks)
        try deleteHere(marks, in: fix)
        fix.cloud.keepOnServer(marks)
        fix.cloud.awaiting = Array(records.values)
        fix.cloud.shareZoneGone = true
        let report = await ClassroomShareRelease.finishStopped(
            stack: fix.stack, storeID: fix.storeID, environment: fix.cloud.environment()
        )
        #expect(report.stoppedBecause == nil)
        #expect(report.unconfirmed == 0)
        #expect(fix.cloud.awaiting.isEmpty)
    }

    @Test("A mark gone from this Mac while its share zone is gone stops the run, and its copy is kept")
    func vanishedWithZoneGoneKeepsCopy() async throws {
        let fix = try fixture()
        let cloud = fix.cloud
        let container = fix.stack.container
        let mark = fix.departedMarks[1]
        let id = try #require(mark.id)
        let gone = mark.objectID
        let env = cloud.environment { step, batch in
            guard step == .copiesConfirmed, batch.studentKey != nil else { return }
            // The share stops: its zone goes from the server, and the mark from this Mac.
            cloud.shareZoneGone = true
            let context = container.newBackgroundContext()
            await context.perform {
                if let object = try? context.existingObject(with: gone) { context.delete(object) }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause?.hasPrefix("iCloud no longer has your classroom share") == true)
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        #expect(fix.stack.viewContext.safeFetch(request).count == 1) // the private copy
    }

    // MARK: - #41: the preview's words

    @Test("This year's marks of a child no longer in the notebook aren't called marks from before the start")
    func goneChildsThisYearMarks() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let gone = UUID().uuidString
        for offset in [-50, 12] {
            let record = CDAttendanceRecord(context: ctx)
            record.studentID = gone
            record.date = huntDay(offset)
            record.status = .present
            try ctx.obtainPermanentIDs(for: [record])
            fix.cloud.share([record.objectID])
        }
        #expect(CoreDataTestHelpers.save(ctx))
        let scope = ClassroomShareScope(cutoff: huntDay(0))
        let rows = try await ClassroomShareRelease.rows(
            container: fix.stack.container, storeID: fix.storeID, pinnedZone: Self.shareZone,
            scope: scope, environment: fix.cloud.environment()
        )
        let shown = await ClassroomShareRelease.preview(rows, cutoff: scope.cutoff, container: fix.stack.container)
        #expect(shown.olderAttendanceOfChildrenWhoLeft == 1)
        #expect(shown.thisYearsAttendanceOfChildrenGone == 1)
        #expect(ClassroomReleaseSheet.goneLine(1) == "1 attendance mark from this school year, "
            + "for a child no longer in your notebook, stops being shared too.")
    }

    // MARK: - #53: the run's saves are the app's own

    @Test("Every save the run makes carries the app's author, as every other writer's does")
    func runSavesCarryAuthor() async throws {
        let fix = try fixture()
        let seen = SeenAuthors()
        let coordinator = fix.stack.container.persistentStoreCoordinator
        let viewContext = fix.stack.viewContext
        let observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.willSaveObjectsNotification, object: nil, queue: nil
        ) { note in
            guard let context = note.object as? NSManagedObjectContext, context !== viewContext,
                  context.persistentStoreCoordinator === coordinator else { return }
            seen.add(context.transactionAuthor)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        let authors = seen.all
        #expect(!authors.isEmpty)
        #expect(authors.allSatisfy { $0 == PersistentHistoryProcessor.transactionAuthor })
    }
}

/// The authors of the saves a test saw, from whichever queue saved.
nonisolated final class SeenAuthors: Sendable {
    private let authors = Mutex<[String?]>([])

    func add(_ author: String?) { authors.withLock { $0.append(author) } }

    var all: [String?] { authors.withLock { $0 } }
}
