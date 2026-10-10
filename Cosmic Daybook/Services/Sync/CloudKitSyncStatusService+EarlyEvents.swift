import CoreData
import Foundation
import OSLog

// MARK: - Events from the moment the stores open
//
// `configure` runs only after the window's bootstrap, and never on a launch
// with no window (a Siri intent, the MCP server). The setup events
// `loadPersistentStores` posts came before it, so a setup failure at launch (a
// schema refusal, no account) went unseen and Settings said "iCloud sync is
// on". The event stream now starts when the stores open
// (`AppBootstrapping.startStoreObservers`) and holds what arrives until
// `configure` hands it to the handlers.

/// A CloudKit event's values, read off the message when it arrives.
struct CloudKitEventValues {
    let type: NSPersistentCloudKitContainer.EventType
    let isFinished: Bool
    let succeeded: Bool
    let error: (any Error)?
    let startDate: Date
    let storeIdentifier: String?
}

extension CloudKitEventValues {
    init(_ event: NSPersistentCloudKitContainer.Event) {
        self.init(
            type: event.type, isFinished: event.endDate != nil, succeeded: event.succeeded,
            error: event.error, startDate: event.startDate, storeIdentifier: event.storeIdentifier
        )
    }
}

extension CloudKitSyncStatusService {

    /// Finished events kept for `configure`. A launch that never configures
    /// (Siri, the MCP server) mustn't grow the list for hours; the newest are kept.
    static let earlyEventLimit = 100

    /// Starts the CloudKit event stream for `stack` as soon as its stores are
    /// open, before `configure`. Events wait until `configure` runs with the
    /// same stack, then go to the handlers in the order they came.
    func beginEarlyEventCapture(for stack: CoreDataStack) {
        if !handlesCloudKitEvents { earlyCaptureStack = stack }
        startCloudKitEventStream()
    }

    /// `configure`'s call: handles from now on, after the events buffered for
    /// this stack. Another stack's buffered events say nothing about this one.
    func startHandlingCloudKitEvents(for stack: CoreDataStack) {
        let buffered = earlyCaptureStack === stack ? bufferedEvents : []
        bufferedEvents = []
        earlyCaptureStack = nil
        handlesCloudKitEvents = true
        if !buffered.isEmpty {
            Self.logger.debug("Handling \(buffered.count) CloudKit event(s) from before sync status started")
        }
        for event in buffered { handleCloudKitEvent(event) }
        startCloudKitEventStream()
    }

    /// Makes the one event stream, if it isn't running yet. The stream is
    /// made here, not inside the task, so nothing posted before the task
    /// first runs is missed; the buffer is generous because a dropped
    /// "finished" event would leave the syncing indicator on.
    func startCloudKitEventStream() {
        guard cloudKitEventTask == nil else { return }
        let events = NotificationCenter.default.messages(
            of: NSPersistentCloudKitContainer.self, for: .eventChanged, bufferSize: 256
        )
        cloudKitEventTask = Task { [weak self] in
            for await message in events {
                guard let self else { return }
                self.receive(CloudKitEventValues(message.event))
            }
        }
    }

    /// One event from the stream: handled, or kept until `configure`. Only
    /// finished events are kept; a started one only turns the spinner on.
    /// Whether the iCloud account holds filing into the classroom share is
    /// followed here, as each event arrives, before `configure` too (a launch
    /// with no window never configures, and Siri's marks are filed all the
    /// same), and only here, so a buffered event isn't counted twice.
    func receive(_ event: CloudKitEventValues) {
        followAccountReadiness(event)
        guard handlesCloudKitEvents else {
            guard event.isFinished else { return }
            bufferedEvents.append(event)
            if bufferedEvents.count > Self.earlyEventLimit { bufferedEvents.removeFirst() }
            return
        }
        handleCloudKitEvent(event)
    }

    func handleCloudKitEvent(_ event: CloudKitEventValues) {
        handleCloudKitEvent(
            type: event.type, isFinished: event.isFinished, succeeded: event.succeeded,
            error: event.error, startDate: event.startDate, storeIdentifier: event.storeIdentifier
        )
    }
}
