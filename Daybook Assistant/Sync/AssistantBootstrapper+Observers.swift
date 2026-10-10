import Foundation
import CoreData

// What the bootstrapper follows for as long as the app runs: the class
// arriving or leaving by sync, and her joining by invitation.

extension AssistantBootstrapper {
    /// A membership row can also arrive by sync rather than by accepting a
    /// link here: on a new iPhone, or after signing in, for an Apple Account
    /// that joined before. Nothing posts `.didJoinClassroom` then, so until
    /// this device has a classroom every import re-reads the row; once it
    /// has one, every change to the private store, where the rows live,
    /// checks they're still there (`followLeaveElsewhere`), and each of the
    /// class's imports that its share is still there (`checkStillInClass`).
    /// Every import, the sample's included, also brings the pickup reminders
    /// up to date (`pickupRemindersMayHaveChanged`).
    ///
    /// Her marks, Restock and her name all go to the shared store, so they
    /// no longer read the membership rows again (they did on every save).
    /// They still get the share check: telling her saves from the guide's
    /// there takes a read of the store's history on every change, imports
    /// included, which costs about what the check's one read at a time does.
    func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = Task { [weak self] in
            // Only the store's identifier comes across: `Notification` isn't Sendable.
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange)
                .map { $0.userInfo?[NSStoreUUIDKey] as? String }
            for await storeID in changes {
                guard let self else { return }
                pickupRemindersMayHaveChanged()
                if AssistantSampleClass.isChosen {
                    // The sample has no membership row of its own, so reading
                    // it here took every import (the real class's on coming
                    // back to the app, or the sample's own saves) for a Leave
                    // elsewhere and threw her back to joining. Only a
                    // classroom arriving underneath matters now, which the
                    // sample's own saves can't bring.
                    if Self.mayBringRealClass(storeID: storeID, sampleStoreIDs: sampleStoreIDs()),
                       AssistantSampleClass.realClassHasMembership() {
                        leaveSampleClass()
                    }
                    continue
                }
                switch phase {
                case .needsClassroom:
                    refreshMembership()
                case .ready:
                    let privateStoreID = coreDataStack?.privatePersistentStore?.identifier
                    if Self.mayChangeMembership(storeID: storeID, privateStoreID: privateStoreID) {
                        await followLeaveElsewhere()
                    }
                    if storeID == nil || storeID == coreDataStack?.sharedPersistentStore?.identifier {
                        checkStillInClass()
                    }
                case .starting, .failed:
                    break
                }
            }
        }
    }

    /// Whether a change to `storeID` can have taken her membership row away:
    /// only a write to the private store can, the one place the rows live
    /// (`CoreDataStack.privateEntityNames`). A change from a store it can't
    /// name counts. Pure, for the tests.
    nonisolated static func mayChangeMembership(storeID: String?, privateStoreID: String?) -> Bool {
        guard let storeID, let privateStoreID else { return true }
        return storeID == privateStoreID
    }

    /// Whether a change while the sample is open can be the real class
    /// arriving: anything but a write to the sample's own store, which only
    /// her taps in the sample make (it has no iCloud). Pure, for the tests.
    nonisolated static func mayBringRealClass(storeID: String?, sampleStoreIDs: Set<String>) -> Bool {
        guard let storeID else { return true }
        return !sampleStoreIDs.contains(storeID)
    }

    /// The sample's own stores, while the screens are on it.
    private func sampleStoreIDs() -> Set<String> {
        guard let stack = coreDataStack, stack !== AssistantStack.current else { return [] }
        return Set(stack.container.persistentStoreCoordinator.persistentStores.compactMap(\.identifier))
    }

    /// ClassroomSharingService does the accepting and posts once the
    /// membership row is written, however long CloudKit took.
    func observeAcceptance() {
        guard acceptanceObserver == nil else { return }
        acceptanceObserver = NotificationCenter.default.addObserver(
            forName: .didJoinClassroom,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Joined while looking at the sample: the real class wins.
                self?.leaveSampleClass()
                self?.refreshMembership()
                // A name she gave before (in the sample, or another class)
                // joins this class's list.
                self?.writeWaitingName()
            }
        }
    }
}
