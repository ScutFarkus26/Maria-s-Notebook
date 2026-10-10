import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

extension ClassroomNamesSuites {

    /// A zone lookup CloudKit never answers (bug hunt 2026-10-09, #7). Apple
    /// documents no time limit for `recordIDs(for:)`, and one that never returned
    /// held the name list's gate, so no name could be saved until relaunch. Now
    /// the wait ends after `zoneLookupTimeLimit`, the gate moves on, and while the
    /// stuck call is out new lookups get no answer at once.
    @Suite("Classroom names: a lookup that never returns", .serialized)
    @MainActor
    struct ClassroomNamesTimeLimitTests {

        private typealias Support = ClassroomNamesTestSupport

        private let classroom = "com.apple.coredata.cloudkit.share.NOW"

        private func at(_ seconds: TimeInterval) -> Date {
            Support.at(seconds)
        }

        private func everyone(in context: NSManagedObjectContext) -> [CDClassroomPerson] {
            context.safeFetch(CDFetchRequest(CDClassroomPerson.self))
        }

        /// A lookup that answers at once that nothing has been sent.
        private let answering: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { _ in [:] }

        /// A lookup CloudKit never answers, until the test lets it go: it parks
        /// a pool thread the way a stuck `recordIDs(for:)` does.
        nonisolated private final class StuckLookup: Sendable {
            private let released = DispatchSemaphore(value: 0)
            private let asked = Mutex(0)

            var calls: Int { asked.withLock { $0 } }

            func lookUp(_ ids: [NSManagedObjectID]) -> [NSManagedObjectID: String] {
                asked.withLock { $0 += 1 }
                released.wait()
                return [:]
            }

            func release() {
                released.signal()
            }
        }

        @Test("A lookup that never returns lets the gate go: the name waits, and the next lookup gets no answer at once",
              .timeLimit(.minutes(1)))
        func lookupThatNeverReturns() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            let row = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
            #expect(context.safeSave())
            let stuck = StuckLookup()
            defer { stuck.release() }
            let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { stuck.lookUp($0) }

            try await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
                try await ClassroomNames.$zoneLookupTimeLimit.withValue(.milliseconds(200)) {
                    try await Support.asDevice(recordName: "_guide") {
                        let set = await ClassroomNames.setMyName("Dan", role: .leadGuide, in: context)
                        if case .waiting = set {} else { Issue.record("expected the name to wait, got \(set)") }
                        #expect(ClassroomIdentity.nameWaitingAs == .leadGuide, "written later, by writeWaitingName")
                        #expect(ClassroomIdentity.displayName == "Dan")
                        #expect(row.displayName == "Danny", "no row written without an answer")
                        #expect(everyone(in: context).count == 1, "and no second row made for him")
                        #expect(ClassroomNames.lookupOut != nil, "the lookup is still out")

                        // The gate is free, and nobody parks a second pool thread.
                        let started = ContinuousClock.now
                        #expect(await ClassroomNames.foldMyRows(role: .leadGuide, in: context) == 0)
                        await ClassroomNames.warmZones(in: context, arrival: nil)
                        #expect(ContinuousClock.now - started < .milliseconds(150), "no answer at once, not after a wait")
                        #expect(stuck.calls == 1)

                        // Once it returns (its late answer dropped), lookups are asked again.
                        stuck.release()
                        await ClassroomNames.lookupOut?.value
                        #expect(ClassroomNames.lookupOut == nil)
                        let answered = await ClassroomNames.$zoneLookupOverride.withValue(answering) {
                            await ClassroomNames.setMyName("Dan", role: .leadGuide, in: context)
                        }
                        let written = try #require(answered.written)
                        #expect(written.person.objectID == row.objectID)
                        #expect(row.displayName == "Dan")
                        #expect(ClassroomIdentity.nameWaitingAs == nil)
                    }
                }
            }
        }

        // Review 2026-10-09: a name saved in Settings while the lookup was stuck
        // waited for a relaunch on a Mac left open.
        @Test("A name saved while a lookup runs out of time goes in after the next import", .timeLimit(.minutes(1)))
        func timedOutNameGoesInAfterTheNextImport() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            let row = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
            let membership = CDClassroomMembership(context: context)
            membership.role = .leadGuide
            membership.classroomZoneID = classroom
            #expect(context.safeSave())
            let stuck = StuckLookup()
            defer { stuck.release() }
            let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { stuck.lookUp($0) }
            let arrival = ClassroomNames.Arrival()
            for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
                arrival.noteImport(intoStoreWithIdentifier: store.identifier ?? "", startedAt: Date())
            }

            await Support.asDevice(recordName: "_guide") {
                let set = await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
                    await ClassroomNames.$zoneLookupTimeLimit.withValue(.milliseconds(200)) {
                        await ClassroomNames.setMyName("Dan", role: .leadGuide, in: context, arrival: arrival)
                    }
                }
                if case .waiting = set {} else { Issue.record("expected the name to wait, got \(set)") }
                #expect(row.displayName == "Danny")
                stuck.release()
                await ClassroomNames.lookupOut?.value

                await ClassroomNames.$zoneLookupOverride.withValue(answering) {
                    arrival.noteImport(intoStoreWithIdentifier: "another", startedAt: Date())
                    await arrival.importWork?.value
                }
                #expect(row.displayName == "Dan", "no relaunch needed")
                #expect(ClassroomIdentity.nameWaitingAs == nil)
                #expect(!context.hasChanges, "saved")
            }
        }

        @Test("A waiting write whose lookup runs out of time tries again after the next import",
              .timeLimit(.minutes(1)))
        func timedOutWriteWaitsForTheNextImport() async throws {
            let context = try CoreDataTestHelpers.makeContext()
            let row = Support.person("_guide", "Danny", role: .leadGuide, created: at(0), in: context)
            let membership = CDClassroomMembership(context: context)
            membership.role = .leadGuide
            membership.classroomZoneID = classroom
            #expect(context.safeSave())
            let stuck = StuckLookup()
            defer { stuck.release() }
            let lookup: @Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String] = { stuck.lookUp($0) }
            let arrival = ClassroomNames.Arrival()
            for store in context.persistentStoreCoordinator?.persistentStores ?? [] {
                arrival.noteImport(intoStoreWithIdentifier: store.identifier ?? "", startedAt: Date())
            }

            await Support.asDevice(recordName: "_guide", displayName: "Dan") {
                ClassroomNames.markWaiting(as: .leadGuide)
                let wrote = await ClassroomNames.$zoneLookupOverride.withValue(lookup) {
                    await ClassroomNames.$zoneLookupTimeLimit.withValue(.milliseconds(200)) {
                        await ClassroomNames.writeWaitingName(in: context, arrival: arrival)
                    }
                }
                #expect(!wrote)
                #expect(row.displayName == "Danny")
                stuck.release()
                await ClassroomNames.lookupOut?.value

                // The next import runs it again, and CloudKit answers this time.
                await ClassroomNames.$zoneLookupOverride.withValue(answering) {
                    arrival.noteImport(intoStoreWithIdentifier: "another", startedAt: Date())
                    await arrival.importWork?.value
                }
                #expect(row.displayName == "Dan")
                #expect(ClassroomIdentity.nameWaitingAs == nil)
                #expect(!context.hasChanges, "saved")
            }
        }
    }
}
