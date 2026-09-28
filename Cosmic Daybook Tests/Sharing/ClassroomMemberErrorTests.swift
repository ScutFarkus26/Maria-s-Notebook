import CloudKit
import Foundation
import Testing
@testable import CosmicDaybook

/// `CKError.participantAlreadyInvited` (iOS/macOS 26) reaches `addMember`
/// bare, inside a partial failure, or wrapped by Core Data's
/// `persistUpdatedShare`; all three must read as "already invited".
@Suite("Classroom member errors")
struct ClassroomMemberErrorTests {

    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> NSError {
        NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    @Test("Already invited is recognised bare, in a partial failure, and wrapped")
    func recognisesAlreadyInvited() {
        let bare = ckError(.participantAlreadyInvited)
        #expect(ClassroomSharingService.isAlreadyInvited(bare))

        let partial = ckError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "share"): bare]
        ])
        #expect(ClassroomSharingService.isAlreadyInvited(partial))

        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: bare])
        #expect(ClassroomSharingService.isAlreadyInvited(wrapped))
    }

    @Test("Other CloudKit errors are not mistaken for it")
    func ignoresOtherErrors() {
        #expect(!ClassroomSharingService.isAlreadyInvited(ckError(.networkFailure)))
        let partial = ckError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "share"): ckError(.permissionFailure)]
        ])
        #expect(!ClassroomSharingService.isAlreadyInvited(partial))
    }
}
