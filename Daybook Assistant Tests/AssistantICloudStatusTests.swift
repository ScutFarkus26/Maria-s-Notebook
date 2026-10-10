import CloudKit
import Testing
@testable import Daybook_Assistant

// Only the states she can do something about get words; an account that's
// fine, or that CloudKit couldn't read just now, says nothing.
@Suite("Assistant iCloud status wording")
struct AssistantICloudStatusTests {

    @Test("Problems she can act on are named; available and unknown stay quiet")
    func wording() {
        #expect(CKAccountStatus.noAccount.assistantProblem?.contains("isn't signed in") == true)
        #expect(CKAccountStatus.restricted.assistantProblem?.contains("blocked") == true)
        #expect(CKAccountStatus.temporarilyUnavailable.assistantProblem != nil)
        #expect(CKAccountStatus.available.assistantProblem == nil)
        #expect(CKAccountStatus.couldNotDetermine.assistantProblem == nil)
    }
}
