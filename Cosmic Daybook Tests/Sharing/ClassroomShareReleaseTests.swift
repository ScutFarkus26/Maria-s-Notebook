import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The fake iCloud for the release tests: it "syncs" instantly — the server holds whatever
/// the store holds, and the share zone holds whatever is marked shared.
nonisolated final class FakeReleaseCloud: @unchecked Sendable {
    static let shareZone = "com.apple.coredata.cloudkit.share.TEST"
    static let defaultZone = "com.apple.coredata.cloudkit.zone"

    let container: NSPersistentCloudKitContainer
    private let lock = NSLock()
    private var shared = Set<NSManagedObjectID>()
    var serverLags = false
    var stop: String?

    init(container: NSPersistentCloudKitContainer) { self.container = container }

    func share(_ ids: [NSManagedObjectID]) {
        lock.lock(); defer { lock.unlock() }
        shared.formUnion(ids)
    }

    func isShared(_ id: NSManagedObjectID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return shared.contains(id)
    }

    func exists(_ id: NSManagedObjectID) -> Bool {
        let context = container.newBackgroundContext()
        return context.performAndWait { (try? context.existingObject(with: id)) != nil }
    }

    typealias StepHook = @Sendable (ClassroomShareRelease.Step, ClassroomShareRelease.Batch) async -> Void

    func environment(afterStep: @escaping StepHook = { _, _ in }) -> ClassroomShareRelease.Environment {
        ClassroomShareRelease.Environment(
            shareZones: { ids in
                let zone = FakeReleaseCloud.shareZone
                return Dictionary(uniqueKeysWithValues: ids.filter(self.isShared).map { ($0, zone) })
            },
            recordIDs: { ids in
                var records: [NSManagedObjectID: CKRecord.ID] = [:]
                for id in ids where !id.isTemporaryID {
                    let zone = self.isShared(id)
                        ? FakeReleaseCloud.shareZone
                        : FakeReleaseCloud.defaultZone
                    records[id] = CKRecord.ID(
                        recordName: id.uriRepresentation().absoluteString,
                        zoneID: CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
                    )
                }
                return records
            },
            serverRecords: { records in
                if self.serverLags { return [:] }
                let coordinator = self.container.persistentStoreCoordinator
                var found: [CKRecord.ID: Date] = [:]
                for record in records {
                    guard let url = URL(string: record.recordName),
                          let id = coordinator.managedObjectID(forURIRepresentation: url),
                          self.exists(id) else { continue }
                    found[record] = Date()
                }
                return found
            },
            stopReason: { self.stop },
            sleep: { _ in try await Task.sleep(for: .milliseconds(1)) },
            patience: .milliseconds(300),
            afterStep: afterStep
        )
    }
}

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
    private func fixture() throws -> Fixture {
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

    private func plan(
        _ fix: Fixture, environment: ClassroomShareRelease.Environment
    ) async throws -> [ClassroomShareRelease.Batch] {
        let rows = try await ClassroomShareRelease.rows(
            container: fix.stack.container, storeID: fix.storeID, pinnedZone: Self.shareZone,
            scope: scope, environment: environment
        )
        return ClassroomShareRelease.plan(rows)
    }

    private func release(
        _ fix: Fixture, _ env: ClassroomShareRelease.Environment
    ) async throws -> ClassroomShareRelease.Report {
        let batches = try await plan(fix, environment: env)
        return await ClassroomShareRelease.run(
            batches, container: fix.stack.container, storeID: fix.storeID, environment: env
        )
    }

    private func count(_ entity: String, in fix: Fixture) -> Int {
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
        let env = fix.cloud.environment()
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

    @Test("A copy carries every attribute the model has")
    func copyFidelity() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        for entityName in ["Student", "AttendanceRecord"] {
            let entity = try #require(ctx.persistentStoreCoordinator?.managedObjectModel.entitiesByName[entityName])
            let original = NSManagedObject(entity: entity, insertInto: ctx)
            for (name, attribute) in entity.attributesByName {
                original.setValue(Self.sample(for: attribute, name: name), forKey: name)
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
                    "\(key)=\(Self.text(object.value(forKey: key)))"
                }
                result["\(entity)|\(id)"] = values.joined(separator: ";")
            }
        }
        return result
    }

    /// A value as text, without object addresses.
    private static func text(_ value: Any?) -> String {
        switch value {
        case let uuid as UUID: return uuid.uuidString
        case let list as [Any]: return list.map { text($0) }.joined(separator: ",")
        case let date as Date: return String(date.timeIntervalSinceReferenceDate)
        case .some(let other): return String(describing: other)
        case .none: return "nil"
        }
    }

    private static func sample(for attribute: NSAttributeDescription, name: String) -> Any? {
        switch attribute.attributeType {
        case .stringAttributeType: return "value of \(name)"
        case .UUIDAttributeType: return UUID()
        case .dateAttributeType: return Date(timeIntervalSinceReferenceDate: Double(name.count) * 1_000)
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: return name.count
        case .doubleAttributeType, .floatAttributeType: return Double(name.count) / 2
        case .booleanAttributeType: return true
        case .transformableAttributeType: return ["a", name] as NSArray
        case .binaryDataAttributeType: return Data(name.utf8)
        default: return nil
        }
    }
}
