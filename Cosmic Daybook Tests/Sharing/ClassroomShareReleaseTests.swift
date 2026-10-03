import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `ClassroomShareRelease`: last year leaves the share by copy → confirm → delete → confirm.
@Suite("Classroom share release")
@MainActor
struct ClassroomShareReleaseTests {

    static let shareZone = FakeReleaseCloud.shareZone

    // MARK: - Fixture

    private let cutoff = AppCalendar.startOfDay(
        AppCalendar.shared.date(from: DateComponents(year: 2026, month: 8, day: 25))!
    )
    private func day(_ offset: Int) -> Date { AppCalendar.shared.date(byAdding: .day, value: offset, to: cutoff)! }
    private var scope: ClassroomShareScope { ClassroomShareScope(cutoff: cutoff) }

    struct Fixture {
        let stack: CoreDataStack
        let cloud: FakeReleaseCloud
        let storeID: String
        let current: CDStudent
        let departed: CDStudent
        let currentOld: [CDAttendanceRecord]
        let currentNew: CDAttendanceRecord
        let departedMarks: [CDAttendanceRecord]
    }

    /// A current child with one mark this year and two last year; a child who left last
    /// year with three marks. Everything shared, as the classroom share holds it today.
    func fixture() throws -> Fixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let current = CDStudent(context: ctx)
        current.firstName = "Maya"
        current.lastName = "Cedar"
        let departed = CDStudent(context: ctx)
        departed.firstName = "Leora"
        departed.lastName = "Birch"
        departed.enrollmentStatus = .transferred
        departed.dateWithdrawn = day(-80)
        departed.nextLessons = ["Bead frame", "Stamp game"] as NSArray
        func mark(_ student: CDStudent, _ offset: Int, note: String? = nil) -> CDAttendanceRecord {
            let record = CDAttendanceRecord(context: ctx)
            record.studentID = student.id?.uuidString ?? ""
            record.date = day(offset)
            record.status = .present
            record.note = note
            return record
        }
        let currentOld = [mark(current, -100), mark(current, -99, note: "Early pickup")]
        let currentNew = mark(current, 6)
        let departedMarks = [mark(departed, -120), mark(departed, -119), mark(departed, -118, note: "Sick")]
        #expect(CoreDataTestHelpers.save(ctx))
        let cloud = FakeReleaseCloud(container: stack.container)
        cloud.share([current, departed].map(\.objectID) + (currentOld + [currentNew] + departedMarks).map(\.objectID))
        let storeID = try #require(stack.container.persistentStoreCoordinator.persistentStores.first?.identifier)
        return Fixture(
            stack: stack, cloud: cloud, storeID: storeID, current: current, departed: departed,
            currentOld: currentOld, currentNew: currentNew, departedMarks: departedMarks
        )
    }

    func plan(
        _ fix: Fixture, environment: ClassroomShareRelease.Environment
    ) async throws -> [ClassroomShareRelease.Batch] {
        let rows = try await ClassroomShareRelease.rows(
            container: fix.stack.container, storeID: fix.storeID, pinnedZone: Self.shareZone,
            scope: scope, environment: environment
        )
        return ClassroomShareRelease.plan(rows)
    }

    func release(
        _ fix: Fixture, _ env: ClassroomShareRelease.Environment
    ) async throws -> ClassroomShareRelease.Report {
        let batches = try await plan(fix, environment: env)
        return await ClassroomShareRelease.run(
            batches, container: fix.stack.container, storeID: fix.storeID, environment: env
        )
    }

    func count(_ entity: String, in fix: Fixture) -> Int {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
        request.resultType = .managedObjectIDResultType
        return (try? fix.stack.viewContext.count(for: request)) ?? -1
    }

    // MARK: - Planning

    @Test("The plan: the departed child and her marks first, then the current child's old marks")
    func planShape() async throws {
        let fix = try fixture()
        let batches = try await plan(fix, environment: fix.cloud.environment())
        #expect(batches.count == 2)
        let child = try #require(batches.first)
        #expect(child.studentKey == fix.departed.id?.uuidString)
        let entities = child.moves.map(\.entity)
        #expect(entities == ["Student", "AttendanceRecord", "AttendanceRecord", "AttendanceRecord"])
        #expect(Set(batches[1].moves.map(\.source)) == Set(fix.currentOld.map(\.objectID)))
        // Nothing of this year moves.
        let moving = Set(batches.flatMap(\.moves).map(\.source))
        #expect(!moving.contains(fix.current.objectID))
        #expect(!moving.contains(fix.currentNew.objectID))
    }

    @Test("Many old marks and no departed child: a small canary slice, then slices of 500")
    func slicing() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        var rows: [ClassroomShareRelease.Row] = []
        for _ in 0..<1_100 {
            let record = CDAttendanceRecord(context: ctx)
            record.studentID = "A"
            rows.append(.init(
                objectID: record.objectID, entity: "AttendanceRecord", recordID: UUID(),
                studentKey: "A", isShared: true, belongs: false
            ))
        }
        let batches = ClassroomShareRelease.plan(rows)
        #expect(batches.map(\.moves.count) == [25, 500, 500, 75])
    }

    // MARK: - Running

    @Test("A full run: last year leaves the share, nothing leaves the notebook, every value intact")
    func fullRun() async throws {
        let fix = try fixture()
        let env = fix.cloud.environment()
        let before = snapshot(fix)
        let students = count("Student", in: fix)
        let marks = count("AttendanceRecord", in: fix)

        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        #expect(report.studentsMoved == 1)
        #expect(report.attendanceMoved == 5)
        #expect(count("Student", in: fix) == students)
        #expect(count("AttendanceRecord", in: fix) == marks)
        #expect(snapshot(fix) == before) // same ids, same values
        // The share now holds this year only, and a second run has nothing to do.
        #expect(try await plan(fix, environment: env).isEmpty)
        #expect(fix.cloud.isShared(fix.current.objectID))
        #expect(fix.cloud.isShared(fix.currentNew.objectID))
    }

    @Test("A copy that vanishes before the delete stops the run and keeps the original")
    func vanishedCopyStops() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesConfirmed else { return }
            // Another device on an old build deletes the private copy.
            let context = container.newBackgroundContext()
            await context.perform {
                let request = NSFetchRequest<NSManagedObject>(entityName: batch.moves[0].entity)
                for object in (try? context.fetch(request)) ?? [] where object.objectID != batch.moves[0].source {
                    let source = try? context.existingObject(with: batch.moves[0].source)
                    if object.value(forKey: "id") as? UUID == source?.value(forKey: "id") as? UUID {
                        context.delete(object)
                    }
                }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause != nil)
        #expect(fix.cloud.exists(fix.departed.objectID)) // the shared original is still there
    }

    @Test("A change to the original after copying is carried to the copy")
    func changeAfterCopyCarried() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let noted = fix.departedMarks[0].objectID
        let env = fix.cloud.environment { step, _ in
            guard step == .copied else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                (try? context.existingObject(with: noted) as? CDAttendanceRecord)?.note = "Changed meanwhile"
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.stoppedBecause == nil)
        let notes = fix.stack.viewContext.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).compactMap(\.note)
        #expect(notes.contains("Changed meanwhile"))
    }

    @Test("When iCloud never confirms the copies, nothing is deleted")
    func serverNeverConfirms() async throws {
        let fix = try fixture()
        fix.cloud.serverLags = true
        let env = fix.cloud.environment(patience: .milliseconds(300)) // gives up on purpose
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(fix.cloud.exists(fix.departed.objectID))
        #expect(fix.departedMarks.allSatisfy { fix.cloud.exists($0.objectID) })
    }

    @Test("A sync problem stops the run before anything is touched")
    func stopReasonStops() async throws {
        let fix = try fixture()
        fix.cloud.stop = "Classroom share export failed"
        let env = fix.cloud.environment()
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause?.contains("Classroom share export failed") == true)
        #expect(count("Student", in: fix) == 2)
    }

    @Test("A run stopped after copying is finished by the next: the copy is reused, not made twice")
    func resumeUsesTwin() async throws {
        let fix = try fixture()
        // The earlier run got as far as the private copy of the departed child.
        let ctx = fix.stack.viewContext
        let twin = NSManagedObject(entity: fix.departed.entity, insertInto: ctx)
        ClassroomShareRelease.copyAttributes(from: fix.departed, to: twin)
        #expect(CoreDataTestHelpers.save(ctx))

        let env = fix.cloud.environment()
        let batches = try await plan(fix, environment: env)
        let studentMove = try #require(batches.first?.moves.first)
        #expect(studentMove.existingTwin == twin.objectID)

        let report = await ClassroomShareRelease.run(
            batches, container: fix.stack.container, storeID: fix.storeID, environment: env
        )
        #expect(report.stoppedBecause == nil)
        #expect(count("Student", in: fix) == 2) // one copy of each child, not three
    }

    @Test("A dropped connection while waiting on iCloud is asked again, not a stop")
    func networkFailureRetried() async throws {
        let fix = try fixture()
        fix.cloud.networkFailuresLeft = 3
        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        #expect(report.batchesDone == report.batchesPlanned)
    }

    @Test("When no export follows a save, one harmless change nudges it, and the run finishes")
    func missingExportNudged() async throws {
        let fix = try fixture()
        // The first save (the copies) is followed by no export; the nudge's is.
        fix.cloud.exportStartAnswers = [false]
        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        #expect(fix.cloud.exportStartQuestions >= 3) // the save, the nudge, and later saves
        // The nudge moved one private copy's modifiedAt by a millisecond and changed nothing else.
        let marks = count("AttendanceRecord", in: fix)
        #expect(marks == 6)
    }

    @Test("A copy carries every attribute the model has")
    func copyFidelity() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        for entityName in ["Student", "AttendanceRecord"] {
            let entity = try #require(ctx.persistentStoreCoordinator?.managedObjectModel.entitiesByName[entityName])
            let original = NSManagedObject(entity: entity, insertInto: ctx)
            for (name, attribute) in entity.attributesByName {
                original.setValue(ReleaseTestValues.sample(for: attribute, name: name), forKey: name)
            }
            let copy = NSManagedObject(entity: entity, insertInto: ctx)
            ClassroomShareRelease.copyAttributes(from: original, to: copy)
            #expect(ClassroomShareRelease.sameAttributes(original, copy), "\(entityName)")
            #expect(copy.objectID != original.objectID)
        }
    }

    // MARK: - Helpers

    /// Every student and mark by id, with its values.
    private func snapshot(_ fix: Fixture) -> [String: String] {
        var result: [String: String] = [:]
        for entity in ["Student", "AttendanceRecord"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in fix.stack.viewContext.safeFetch(request) {
                let id = (object.value(forKey: "id") as? UUID)?.uuidString ?? "?"
                let values = object.entity.attributesByName.keys.sorted().map { key in
                    "\(key)=\(ReleaseTestValues.text(object.value(forKey: key)))"
                }
                result["\(entity)|\(id)"] = values.joined(separator: ";")
            }
        }
        return result
    }
}

// MARK: - A run stopped after its last deletes

extension ClassroomShareReleaseTests {

    @Test("A run stopped after its last batch's deletes is finished: iCloud is checked, then the list clears")
    func finishAfterLastDeletes() async throws {
        let fix = try fixture()
        let cloud = fix.cloud
        // The last batch (the current child's old marks) stops between its delete and the server check.
        let env = cloud.environment { step, batch in
            if step == .originalsDeleted, batch.studentKey == nil { cloud.stop = "Quit partway" }
        }
        let stopped = try await release(fix, env)
        #expect(stopped.stoppedBecause != nil)
        #expect(stopped.batchesDone == stopped.batchesPlanned - 1)
        #expect(try await plan(fix, environment: env).isEmpty) // nothing left for a run to plan
        #expect(cloud.awaiting.count == 2)

        cloud.stop = nil
        let finished = await ClassroomShareRelease.finishStopped(environment: cloud.environment())
        #expect(finished.stoppedBecause == nil)
        #expect(cloud.awaiting.isEmpty)
    }

    @Test("Finishing waits for iCloud: while the originals are still there, the list is kept")
    func finishKeepsListUntilGone() async throws {
        let fix = try fixture()
        let records = await fix.cloud.environment().recordIDs(fix.departedMarks.map(\.objectID))
        fix.cloud.awaiting = Array(records.values) // still on the server
        let env = fix.cloud.environment(patience: .milliseconds(300)) // gives up on purpose
        let report = await ClassroomShareRelease.finishStopped(environment: env)
        #expect(report.stoppedBecause != nil)
        #expect(fix.cloud.awaiting.count == 3)
    }

    @Test("A copy edited after a stopped run keeps the edit; the original's older values don't win")
    func editedTwinKept() async throws {
        let fix = try fixture()
        let ctx = fix.stack.viewContext
        let original = fix.departedMarks[2] // "Sick"
        original.modifiedAt = day(-118)
        // The stopped run's private copy, which the guide then edited.
        let twin = NSManagedObject(entity: original.entity, insertInto: ctx)
        ClassroomShareRelease.copyAttributes(from: original, to: twin)
        twin.setValue("Sick, picked up at 10", forKey: "note")
        twin.setValue(day(-118).addingTimeInterval(3_600), forKey: "modifiedAt")
        #expect(CoreDataTestHelpers.save(ctx))

        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        let notes = ctx.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).compactMap(\.note)
        #expect(notes.contains("Sick, picked up at 10"))
        #expect(!notes.contains("Sick"))
    }

    @Test("A completed run leaves nothing awaiting iCloud")
    func fullRunClearsAwaiting() async throws {
        let fix = try fixture()
        let report = try await release(fix, fix.cloud.environment())
        #expect(report.stoppedBecause == nil)
        #expect(fix.cloud.awaiting.isEmpty)
    }
}
