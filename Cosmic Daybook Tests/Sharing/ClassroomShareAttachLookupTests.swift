import Foundation
import CoreData
import CloudKit
import Testing
@testable import CosmicDaybook

// The Daybook Assistant finds the classroom share after each save that creates
// a mark. It used to read the shares on the main actor; it now reads them off
// it (`classroomShare(inStoreWithIdentifier:…)`). Both forms must give the
// same answer for the same store.

@Suite("Classroom share lookup off the main actor")
@MainActor
struct ClassroomShareAttachLookupTests {

    /// What a lookup came to: the share's zone, nothing, or an error's domain and code.
    private enum Outcome: Equatable {
        case share(String)
        case none
        case failed(String, Int)

        init(_ share: CKShare?) {
            self = share.map { .share($0.recordID.zoneID.zoneName) } ?? .none
        }

        init(_ error: any Error) {
            let ns = error as NSError
            self = .failed(ns.domain, ns.code)
        }
    }

    @Test("the off-main lookup answers as the synchronous one does")
    func offMainMatchesSynchronous() async throws {
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let container = stack.container
        let store = try #require(container.persistentStoreCoordinator.persistentStores.first)
        let storeID = try #require(store.identifier)

        for onlyShareFallback in [false, true] {
            let synchronous: Outcome
            do {
                synchronous = Outcome(try ClassroomShareAttach.classroomShare(
                    in: store, container: container, pinContext: stack.viewContext,
                    onlyShareFallback: onlyShareFallback
                ))
            } catch {
                synchronous = Outcome(error)
            }

            let offMain: Outcome
            do {
                offMain = Outcome(try await ClassroomShareAttach.classroomShare(
                    inStoreWithIdentifier: storeID, container: container, pinContext: stack.viewContext,
                    onlyShareFallback: onlyShareFallback
                ))
            } catch {
                offMain = Outcome(error)
            }

            #expect(offMain == synchronous)
        }
    }

    @Test("a store the container doesn't hold has no shares")
    func unknownStoreHasNoShares() async throws {
        let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
        let shares = try await ClassroomShareAttach.shares(
            inStoreWithIdentifier: UUID().uuidString, container: stack.container
        )
        #expect(shares.isEmpty)
    }
}
