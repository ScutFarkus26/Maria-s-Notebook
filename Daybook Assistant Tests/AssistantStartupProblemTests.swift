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
            #expect(message.contains("from iCloud again"))
        }
    }

    // Bug hunt 2026-10-04: the Home Screen calls the app "Assistant";
    // "Daybook Assistant" is only its TestFlight name.
    @Test("Messages name the app as the Home Screen does")
    func homeScreenName() {
        let errors: [any Error] = [
            CoreDataStackError.storeFromNewerBuild(storeName: "private.sqlite", storeVersion: 12, appVersion: 11),
            CocoaError(.fileReadUnknown)
        ]
        let messages = errors.map { AssistantStartupProblem($0).message }
            + [AssistantStartupProblem(CocoaError(.fileReadUnknown), storesOpen: true).message]
        for message in messages {
            #expect(!message.contains("Daybook Assistant"))
            #expect(message.contains("Assistant"))
        }
        for error in [CoreDataStackError.modelNotFound("x"), .storeLoadFailed(CocoaError(.fileReadUnknown))] {
            #expect(error.errorDescription?.contains("Daybook Assistant") == false)
        }
    }
}
