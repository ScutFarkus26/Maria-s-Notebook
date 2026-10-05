import Foundation
import Testing
@testable import Daybook_Assistant

// The line at the top of the screen that reports a failed save or share:
// up long enough to read.
@Suite("Assistant toasts")
struct AssistantToastTests {

    @Test("A short message stays four seconds, a long one longer, and none past ten")
    func durationByLength() {
        #expect(ToastService.duration(for: "Couldn't save.") == .seconds(4))
        let sentence = "Couldn't send your marks to your guide. They're kept here and go when you're back online."
        let long = ToastService.duration(for: sentence)
        #expect(long > .seconds(4))
        #expect(long < .seconds(10))
        #expect(ToastService.duration(for: String(repeating: "word ", count: 100)) == .seconds(10))
    }
}
