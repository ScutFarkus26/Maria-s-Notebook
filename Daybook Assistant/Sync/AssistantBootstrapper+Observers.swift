import Foundation
import CoreData

// What the bootstrapper follows for as long as the app runs: the class
// arriving or leaving by sync, and her joining by invitation.

extension AssistantBootstrapper {
    /// A membership row can also arrive by sync rather than by accepting a
    /// link here: on a new iPhone, or after signing in, for an Apple Account
    /// that joined before. Nothing posts `.didJoinClassroom` then, so until
    /// this device has a classroom every import re-reads the row; once it
    /// has one, every import checks the rows are still there
    /// (`followLeaveElsewhere`), and each of the class's imports that its
    /// share is still there (`checkStillInClass`). Every import, the
    /// sample's included, also brings the pickup reminders up to date
    /// (`pickupRemindersMayHaveChanged`).
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
                    // classroom arriving underneath matters now.
                    if AssistantSampleClass.realClassHasMembership() { leaveSampleClass() }
                    continue
                }
                switch phase {
                case .needsClassroom:
                    refreshMembership()
                case .ready:
                    await followLeaveElsewhere()
                    if storeID == nil || storeID == coreDataStack?.sharedPersistentStore?.identifier {
                        checkStillInClass()
                    }
                case .starting, .failed:
                    break
                }
            }
        }
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
