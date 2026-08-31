import Foundation
import CoreData
import CloudKit
import OSLog
import Observation

/// Builds the Core Data stack and sharing service, and tracks whether this
/// device has joined a classroom yet.
///
/// The lead guide's app has a long bootstrap of migrations, repairs and
/// backfills. None of it belongs here: the assistant's device owns no data of
/// its own, and every record it sees arrives through the accepted share.
@MainActor
@Observable
final class AssistantBootstrapper {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DaybookAssistant",
        category: "bootstrap"
    )

    enum Phase {
        case starting
        case needsClassroom
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    private(set) var coreDataStack: CoreDataStack?
    private(set) var sharingService: ClassroomSharingService?

    private var acceptanceObserver: (any NSObjectProtocol)?

    func start() async {
        guard case .starting = phase else { return }

        do {
            let stack = try CoreDataStack()
            coreDataStack = stack

            let service = ClassroomSharingService(
                container: stack.container,
                context: stack.viewContext,
                coreDataStack: stack
            )
            sharingService = service

            observeAcceptance()
            refreshMembership()
        } catch {
            Self.logger.error("Assistant bootstrap failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-reads the membership row. Acceptance writes one, and the roster only
    /// starts arriving afterwards, so this is what flips onboarding to the
    /// attendance list.
    func refreshMembership() {
        guard let context = coreDataStack?.viewContext else { return }
        let request = CDFetchRequest(CDClassroomMembership.self)
        request.fetchLimit = 1
        let hasMembership = context.safeFetchFirst(request) != nil
        phase = hasMembership ? .ready : .needsClassroom
    }

    private func observeAcceptance() {
        guard acceptanceObserver == nil else { return }
        acceptanceObserver = NotificationCenter.default.addObserver(
            forName: .didAcceptCloudKitShare,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // ClassroomSharingService does the accepting; wait a beat for it to
            // write the membership row before re-reading.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.refreshMembership()
            }
        }
    }
}
