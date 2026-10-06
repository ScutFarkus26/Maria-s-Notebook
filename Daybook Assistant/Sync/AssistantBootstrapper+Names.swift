import Foundation
import CloudKit
import OSLog
import UIKit

// Her name in the classroom's list (`ClassroomNames`), and the iCloud account
// it's written under. A name she set where it couldn't go in (the Sample
// Class, offline, before joining) used to wait for the next cold launch, and
// leaving and joining again never wrote it. After an Apple Account change her
// row could go under the last account's record name.

extension AssistantBootstrapper {
    private static let namesLogger = Logger.app(category: "names")

    /// Her name from iCloud on a new iPhone, now or when key-value storage
    /// catches up, so setup's name page is already filled in.
    func restoreName() {
        AssistantNameStore.restoreIfNeeded()
        guard nameObserver == nil else { return }
        nameObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = AssistantNameStore.restoreIfNeeded() }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Asks now, and again whenever the account changes (signed out in
    /// Settings, say), for as long as the app runs.
    func observeAccountChanges() {
        guard accountObserver == nil else { return }
        accountObserver = Task { [weak self] in
            await self?.refreshAccountStatus()
            let changes = NotificationCenter.default.notifications(named: .CKAccountChanged).map { _ in () }
            for await _ in changes {
                await self?.accountChanged()
            }
        }
    }

    /// The account's status, and who is signed in now. No name row is
    /// written until that's known.
    func accountChanged() async {
        let before = knownRecordName
        AssistantNameStore.writesHeld = true
        await refreshAccountStatus()
        await readAccountAgain(before: before)
    }

    /// Reads who is signed in, compares it with `before`, and lets name rows
    /// be written again. Another account means the name here was the last
    /// one's: hers comes from her iCloud copy, or she's asked. Not read
    /// (signed out, offline), writes stay held until the next account change
    /// or return to the app.
    func readAccountAgain(before: String?) async {
        let now: String
        do {
            now = try await fetchUserRecordName()
        } catch {
            let detail = error.localizedDescription
            Self.namesLogger.notice("Couldn't read the iCloud account after it changed: \(detail, privacy: .public)")
            return
        }
        // `ClassroomIdentity`'s saved ID, which her row is written under.
        await ClassroomIdentity.refreshRecordName()
        if AssistantNameStore.isAnotherAccount(before: before, now: now) {
            Self.namesLogger.notice("Another Apple Account signed in; asking for her name again")
            AssistantNameStore.forgetForNewAccount()
            askForNameAgain = ClassroomIdentity.displayName == nil && isInRealClass
        }
        knownRecordName = ClassroomIdentity.realRecordName(now) ?? knownRecordName
        AssistantNameStore.writesHeld = false
        writeWaitingName()
    }

    /// What `install` learns of the account at launch or after a rebuild,
    /// unless an account change is being read.
    /// At launch or after a rebuild, once the record name is read again: if
    /// another Apple Account signed in while the app was closed, the last
    /// person's name mustn't be written under the new account's ID.
    func noteAccountAtLaunch(before: String?) {
        if AssistantNameStore.isAnotherAccount(before: before, now: ClassroomIdentity.currentUserRecordName) {
            Self.namesLogger.notice("Another Apple Account since the last launch; asking for her name again")
            AssistantNameStore.forgetForNewAccount()
            askForNameAgain = ClassroomIdentity.displayName == nil && isInRealClass
        }
        noteKnownAccount()
    }

    func noteKnownAccount() {
        guard !AssistantNameStore.writesHeld, let name = ClassroomIdentity.currentUserRecordName else { return }
        knownRecordName = name
    }

    /// Coming back to the app: a name that waited goes in, or the account
    /// that couldn't be read after a change is read again.
    func observeReturnToForeground() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.returnedToForeground() }
        }
    }

    private func returnedToForeground() {
        guard AssistantNameStore.writesHeld else {
            writeWaitingName()
            return
        }
        let before = knownRecordName
        Task { await readAccountAgain(before: before) }
    }

    /// A name she set where it couldn't go into the class's list yet goes in
    /// now: after joining, after leaving the Sample Class, on coming back to
    /// the app, and once an account change is read. Only in the real class,
    /// and not while she's being asked for her name.
    func writeWaitingName() {
        guard isInRealClass, !askForNameAgain, let stack = coreDataStack else { return }
        AssistantNameStore.writeWaitingName(on: stack)
    }

    private var isInRealClass: Bool {
        guard case .ready = phase else { return false }
        return !AssistantSampleClass.isActive
    }
}
