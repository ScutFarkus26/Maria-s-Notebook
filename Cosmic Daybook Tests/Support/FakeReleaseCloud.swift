import CloudKit
import CoreData
import Foundation
import Synchronization
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
    /// The share's zone is gone from the server (the share was stopped): its records are
    /// answered with `CloudKitServerCheck.ZoneMissing`, as the server's `zoneNotFound` is.
    var shareZoneGone = false
    /// Server calls that fail with a network error before the server answers.
    var networkFailuresLeft = 0
    /// Answers to "did an export start?", in order; then true.
    var exportStartAnswers: [Bool] = []
    private(set) var exportStartQuestions = 0

    func nextExportStartAnswer() -> Bool {
        lock.lock(); defer { lock.unlock() }
        exportStartQuestions += 1
        return exportStartAnswers.isEmpty ? true : exportStartAnswers.removeFirst()
    }

    func takeNetworkFailure() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard networkFailuresLeft > 0 else { return false }
        networkFailuresLeft -= 1
        return true
    }

    init(container: NSPersistentCloudKitContainer) { self.container = container }

    /// The run's list of originals awaiting iCloud's confirmation (the app keeps it in UserDefaults).
    private var awaitingGone: [CKRecord.ID] = []

    var awaiting: [CKRecord.ID] {
        get { lock.lock(); defer { lock.unlock() }; return awaitingGone }
        set { lock.lock(); defer { lock.unlock() }; awaitingGone = newValue }
    }

    func share(_ ids: [NSManagedObjectID]) {
        lock.lock(); defer { lock.unlock() }
        shared.formUnion(ids)
    }

    func isShared(_ id: NSManagedObjectID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return shared.contains(id)
    }

    /// Records the server keeps after they're deleted here (an import that dropped them, not a delete).
    private var keptOnServer = Set<NSManagedObjectID>()

    func keepOnServer(_ ids: [NSManagedObjectID]) {
        lock.lock(); defer { lock.unlock() }
        keptOnServer.formUnion(ids)
    }

    func isKeptOnServer(_ id: NSManagedObjectID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keptOnServer.contains(id)
    }

    func exists(_ id: NSManagedObjectID) -> Bool {
        let context = container.newBackgroundContext()
        return context.performAndWait { (try? context.existingObject(with: id)) != nil }
    }

    typealias StepHook = @Sendable (ClassroomShareRelease.Step, ClassroomShareRelease.Batch) async -> Void

    /// The give-up for a run that is meant to finish: a number of waits, not a clock. The
    /// product's give-up is a wall-clock deadline, and on 2026-10-01 a loaded parallel run
    /// took longer than 300 ms to get past three network failures. With this, load can slow
    /// such a run but never fail it; a regression that keeps it waiting still fails fast.
    static let finishingWaits = 100

    /// The waits a run made, for the attempt limit.
    private var waits = 0

    struct GaveUp: LocalizedError {
        var errorDescription: String? { "The fake iCloud's attempt limit ran out." }
    }

    func countWait(limit: Int?) throws {
        lock.lock(); defer { lock.unlock() }
        waits += 1
        if let limit, waits > limit { throw GaveUp() }
    }

    /// `patience` nil (a run meant to finish): no clock deadline, give up after
    /// `finishingWaits` waits. A test that times out on purpose (`serverLags`) passes a short
    /// patience so the product's own deadline is what stops it.
    func environment(
        patience: Duration? = nil,
        afterStep: @escaping StepHook = { _, _ in }
    ) -> ClassroomShareRelease.Environment {
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
            serverRecords: { try self.serverAnswer($0) },
            stopReason: { self.stop },
            sleep: { _ in
                try self.countWait(limit: patience == nil ? FakeReleaseCloud.finishingWaits : nil)
                try await Task.sleep(for: .milliseconds(1))
            },
            patience: patience ?? .seconds(3_600),
            exportStarted: { _ in self.nextExportStartAnswer() },
            afterStep: afterStep,
            awaitingGone: { self.awaiting },
            setAwaitingGone: { self.awaiting = $0 },
            heldHere: { self.heldHere($0) }
        )
    }

    /// What the fake server holds of `records`: those whose object is here or kept on the
    /// server, each dated now. Records in the share zone throw `ZoneMissing` while
    /// `shareZoneGone`.
    func serverAnswer(_ records: [CKRecord.ID]) throws -> [CKRecord.ID: Date] {
        if takeNetworkFailure() { throw CKError(.networkFailure) }
        if serverLags { return [:] }
        var found: [CKRecord.ID: Date] = [:]
        var inMissingZones = Set<CKRecord.ID>()
        for record in records {
            if shareZoneGone, record.zoneID.zoneName == FakeReleaseCloud.shareZone {
                inMissingZones.insert(record)
                continue
            }
            guard let id = objectID(of: record), exists(id) || isKeptOnServer(id) else { continue }
            found[record] = Date()
        }
        if !inMissingZones.isEmpty {
            throw CloudKitServerCheck.ZoneMissing(found: found, inMissingZones: inMissingZones)
        }
        return found
    }

    /// Of `records`, those whose object is in the store.
    func heldHere(_ records: [CKRecord.ID]) -> Set<CKRecord.ID> {
        Set(records.filter { record in objectID(of: record).map(exists) ?? false })
    }

    /// The object a fake record names: its record name is the object's URI.
    private func objectID(of record: CKRecord.ID) -> NSManagedObjectID? {
        guard let url = URL(string: record.recordName) else { return nil }
        return container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url)
    }
}

/// True the first time it's asked, false after: a step hook that acts once.
nonisolated final class ReleaseTestOnce: Sendable {
    private let done = Mutex(false)

    func claim() -> Bool {
        done.withLock { done in
            defer { done = true }
            return !done
        }
    }
}

/// Values for the release tests: attribute samples and address-free text.
nonisolated enum ReleaseTestValues {
    /// A value as text, without object addresses.
    static func text(_ value: Any?) -> String {
        switch value {
        case let uuid as UUID: return uuid.uuidString
        case let list as [Any]: return list.map { text($0) }.joined(separator: ",")
        case let date as Date: return String(date.timeIntervalSinceReferenceDate)
        case .some(let other): return String(describing: other)
        case .none: return "nil"
        }
    }

    static func sample(for attribute: NSAttributeDescription, name: String) -> Any? {
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
