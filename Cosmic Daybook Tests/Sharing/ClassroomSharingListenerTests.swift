import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The participant list is refreshed on remote changes only while a screen
/// that shows it is open; nothing listens before or after.
@Suite("Classroom sharing: participant listener lifetime")
@MainActor
struct ClassroomSharingListenerTests {

    @Test("The listener runs only between start and the last matching stop")
    func listenerFollowsScreens() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        #expect(service.isObservingParticipants == false)

        service.startObservingParticipants()
        service.startObservingParticipants()
        #expect(service.isObservingParticipants)

        service.stopObservingParticipants()
        #expect(service.isObservingParticipants)
        service.stopObservingParticipants()
        #expect(service.isObservingParticipants == false)

        // An unbalanced stop does not go negative and break the next start.
        service.stopObservingParticipants()
        service.startObservingParticipants()
        #expect(service.isObservingParticipants)
        service.stopObservingParticipants()
        #expect(service.isObservingParticipants == false)
    }
}
