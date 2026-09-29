import Foundation
import Testing
@testable import Daybook_Assistant

// The "Can't start" screen speaks the Assistant's language: never the
// notebook's name or its Settings → Database path.
@Suite("Assistant startup problems")
struct AssistantStartupProblemTests {

    @Test("An older build over a newer store says to install the latest from TestFlight")
    func newerStore() {
        let problem = AssistantStartupProblem(
            CoreDataStackError.storeFromNewerBuild(storeName: "shared.sqlite", storeVersion: 12, appVersion: 11)
        )
        #expect(problem.message.contains("Install the latest version from TestFlight"))
    }

    @Test("No message names the notebook or its settings")
    func noNotebookWording() {
        let errors: [any Error] = [
            CoreDataStackError.storeFromNewerBuild(storeName: "private.sqlite", storeVersion: 12, appVersion: 11),
            CoreDataStackError.storeSchemaIncoherent(storeName: "private.sqlite", detail: "ZSTUDENT.ZLEFTAT"),
            CoreDataStackError.cloudKitLoadFailed(CocoaError(.fileReadCorruptFile)),
            CocoaError(.fileReadUnknown)
        ]
        for error in errors {
            let message = AssistantStartupProblem(error).message
            #expect(!message.contains("Cosmic Daybook"))
            #expect(!message.contains("Settings"))
            #expect(message.contains("rebuild") || message.contains("Rebuild"))
        }
    }
}
