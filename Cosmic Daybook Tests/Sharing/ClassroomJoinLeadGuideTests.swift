import CloudKit
import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29, part 2 #4: a lead guide's notebook accepted another
/// guide's invitation, and Leave then did nothing (the notebook reads its
/// lead guide's row over the assistant's row the join wrote). It now refuses,
/// in plain words.
@Suite("Classroom joining: a lead guide's notebook refuses another class")
@MainActor
struct ClassroomJoinLeadGuideTests {

    @Test("A notebook that leads its own class refuses another guide's invitation, never its own share's")
    func leadGuideRefuses() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let service = ClassroomSharingService(container: stack.container, context: context)
        #expect(!service.leadsItsOwnClass(invitedAs: .privateUser), "no class of its own yet: it may join")

        ClassroomRepository(context: context).pinClassroom(
            zoneName: "com.apple.coredata.cloudkit.share.MINE", role: .leadGuide, ownerIdentity: "__defaultOwner__"
        )
        try context.save()
        #expect(service.leadsItsOwnClass(invitedAs: .privateUser))
        #expect(service.leadsItsOwnClass(invitedAs: .publicUser))
        #expect(!service.leadsItsOwnClass(invitedAs: .owner), "the invitation to its own share")
    }

    @Test("A notebook that joined as an assistant isn't refused here")
    func assistantIsNotRefusedHere() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        ClassroomRepository(context: context).createMembership(
            classroomZoneID: "com.apple.coredata.cloudkit.share.ABC", role: .assistant, ownerIdentity: "_rivera"
        )
        try context.save()
        let service = ClassroomSharingService(container: stack.container, context: context)
        #expect(!service.leadsItsOwnClass(invitedAs: .privateUser))
    }

    @Test("The refusal says what happened and what to do, in plain words")
    func refusalIsPlain() {
        let message = ClassroomJoinRefusal.leadsOwnClass.message
        #expect(message.contains("your own class"))
        #expect(message.contains("Daybook Assistant"))
        #expect(!message.contains("share") && !message.contains("zone") && !message.contains("CloudKit"))
    }
}
