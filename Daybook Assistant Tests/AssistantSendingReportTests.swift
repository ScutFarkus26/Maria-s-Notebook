import Foundation
import Testing
@testable import Daybook_Assistant

// 2026-10-23: the text file she shares from the Classroom screen when marks
// won't send. The log itself comes from the process's own log store, which
// a test can't fill, so the pure parts are checked: the standing lines, which
// of Core Data's lines are kept, and the file's shape.
@Suite("Assistant sending report")
struct AssistantSendingReportTests {

    @Test("The report says what the phone reports, what waits, and the class, in plain words, then the log")
    func text() {
        let standing = AssistantSendingReport.Standing(
            version: "1.1 (26)",
            system: "iOS 26.4.1",
            now: Date(timeIntervalSince1970: 1_000_000),
            network: .init(usable: true, interface: .wifi, lowDataMode: true),
            lowPowerMode: false,
            waiting: 3,
            offline: true,
            stuck: false,
            lastEditSave: 0,
            lastExportStart: 900_000,
            lastImportEnd: 950_000,
            classCode: "DB5879EF"
        ).lines
        let report = AssistantSendingReport.text(standing: standing, log: ["10:00:00  shareAttach  error: stalled"])
        #expect(report.hasPrefix("Daybook Assistant log\nVersion 1.1 (26), iOS 26.4.1\n"))
        #expect(report.contains("Network: Wi-Fi, usable, Low Data Mode on\n"))
        #expect(report.contains("Low Power Mode: off\n"))
        #expect(report.contains("Marks waiting to send: 3 (iCloud couldn't be reached on the last try)\n"))
        #expect(report.contains("Last edit saved: never; last upload began: "))
        #expect(report.contains("Class code: DB5879EF\n"))
        #expect(report.contains("(1 lines):\n\n10:00:00  shareAttach  error: stalled\n"))

        let unknown = AssistantSendingReport.Standing(
            version: "1.1 (26)", system: "iOS 26.4.1", now: Date(), network: nil, lowPowerMode: true,
            waiting: 0, offline: false, stuck: true, lastEditSave: 0, lastExportStart: 0, lastImportEnd: 0,
            classCode: nil
        ).lines
        let empty = AssistantSendingReport.text(standing: unknown, log: [])
        #expect(empty.contains("Network: not known yet\n"))
        #expect(empty.contains("Low Power Mode: on\n"))
        #expect(empty.contains("Marks waiting to send: 0 (a send has run past its time limit)\n"))
        #expect(empty.contains("Class code: none\n"))
        #expect(empty.hasSuffix("(0 lines):\n\n(nothing yet)\n"))
    }

    @Test("Core Data's lines about uploads, imports, setup and errors are kept; its other chatter isn't")
    func coreDataLines() {
        #expect(AssistantSendingReport.keepsCoreDataLine("Finished automatic export - ExportActivity"))
        #expect(AssistantSendingReport.keepsCoreDataLine("Scheduling automated import with activity (Push)"))
        #expect(AssistantSendingReport.keepsCoreDataLine("CloudKit setup failed because there is another instance"))
        #expect(AssistantSendingReport.keepsCoreDataLine("Request was aborted ... Error Domain=NSCocoaErrorDomain"))
        #expect(!AssistantSendingReport.keepsCoreDataLine("CoreData: annotation: Connecting to sqlite database file"))
    }
}
