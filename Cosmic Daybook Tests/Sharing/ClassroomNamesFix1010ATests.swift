import Foundation
import Testing
@testable import CosmicDaybook

extension ClassroomNamesSuites {

    /// "Your name" said "Saved on this device" for a name an account change then
    /// dropped, and kept it as saved, so leaving the field never saved it again
    /// (bug hunt 2026-10-10, #9). Dropping a waiting name now posts a notice the
    /// card reloads on.
    @Suite("Classroom names: a dropped waiting name is announced", .serialized)
    @MainActor
    struct ClassroomNamesFix1010ATests {

        @Test("Another account confirmed drops the waiting name and posts the notice; nothing waiting, no notice")
        func droppedWaitingNamePostsTheNotice() async {
            await ClassroomNamesTestSupport.asDevice(recordName: "_guide", displayName: "Dan") {
                ClassroomNames.mark(waitingAs: .leadGuide, typedUnder: "_guide")
                let heard = NoticeCount()
                let observer = NotificationCenter.default.addObserver(
                    forName: ClassroomNames.waitingNameForgotten, object: nil, queue: nil
                ) { _ in
                    MainActor.assumeIsolated { heard.count += 1 }
                }
                defer { NotificationCenter.default.removeObserver(observer) }

                // The same account read again: the name keeps waiting, and nothing is posted.
                await ClassroomIdentity.accountChanged { ClassroomIdentity.currentUserRecordName = "_guide" }
                #expect(ClassroomIdentity.nameWaitingAs == .leadGuide)
                #expect(heard.count == 0)

                await ClassroomIdentity.accountChanged { ClassroomIdentity.currentUserRecordName = "_other" }
                #expect(ClassroomIdentity.nameWaitingAs == nil)
                #expect(ClassroomIdentity.displayName == nil)
                #expect(heard.count == 1)

                ClassroomNames.forgetWaitingName()
                #expect(heard.count == 1, "nothing was waiting")
            }
        }
    }
}

/// How many notices a test heard.
@MainActor
private final class NoticeCount {
    var count = 0
}
