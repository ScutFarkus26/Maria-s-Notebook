#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

/// Snapshot tests for attendance email subject and body formatting.
/// These tests verify the text output is consistent and correctly formatted.
@Suite("Attendance Email Snapshots")
@MainActor
struct AttendanceEmailSnapshotTests {

    // MARK: - Subject Line Tests

    @Test("Email subject format")
    func emailSubject_format() {
        let subject = AttendanceEmailReport.makeSubject(
            for: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(subject.contains("Attendance"))
        #expect(!subject.isEmpty)
        assertTextSnapshot(subject, named: "subject")
    }

    // MARK: - Body Tests

    @Test("Email body all present")
    func emailBody_allPresent() {
        let body = AttendanceEmailReport.makeBody(
            present: ["Emma Johnson", "Liam Smith", "Olivia Williams", "Noah Brown", "Ava Davis"],
            tardy: [],
            absent: [],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("On Time"))
        #expect(body.contains("Emma Johnson"))
        assertTextSnapshot(body, named: "allPresent")
    }

    @Test("Email body mixed attendance")
    func emailBody_mixedAttendance() {
        let body = AttendanceEmailReport.makeBody(
            present: ["Emma Johnson", "Liam Smith", "Olivia Williams"],
            tardy: ["Noah Brown"],
            absent: ["Ava Davis"],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("On Time"))
        #expect(body.contains("Tardy"))
        #expect(body.contains("Absent"))
        assertTextSnapshot(body, named: "mixedAttendance")
    }

    @Test("Email body all tardy")
    func emailBody_allTardy() {
        let body = AttendanceEmailReport.makeBody(
            present: [],
            tardy: ["Emma Johnson", "Liam Smith", "Olivia Williams"],
            absent: [],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("Tardy"))
        assertTextSnapshot(body, named: "allTardy")
    }

    @Test("Email body all absent")
    func emailBody_allAbsent() {
        let body = AttendanceEmailReport.makeBody(
            present: [],
            tardy: [],
            absent: ["Emma Johnson", "Liam Smith", "Olivia Williams", "Noah Brown", "Ava Davis"],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("Absent"))
        assertTextSnapshot(body, named: "allAbsent")
    }

    @Test("Email body empty class")
    func emailBody_emptyClass() {
        let body = AttendanceEmailReport.makeBody(
            present: [],
            tardy: [],
            absent: [],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("— none —"))
        assertTextSnapshot(body, named: "emptyClass")
    }

    @Test("Email body single student")
    func emailBody_singleStudent() {
        let body = AttendanceEmailReport.makeBody(
            present: ["Emma Johnson"],
            tardy: [],
            absent: [],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("Emma Johnson"))
        assertTextSnapshot(body, named: "singleStudent")
    }

    @Test("Email body multiple tardy")
    func emailBody_multipleTardy() {
        let body = AttendanceEmailReport.makeBody(
            present: ["Emma Johnson"],
            tardy: ["Liam Smith", "Olivia Williams", "Noah Brown"],
            absent: ["Ava Davis"],
            date: SnapshotDates.reference,
            calendar: snapshotCalendar
        )

        #expect(body.contains("Tardy (3)"))
        assertTextSnapshot(body, named: "multipleTardy")
    }

    // MARK: - Mailto URL Tests

    @Test("Mailto URL structure")
    func mailtoURL_structure() {
        let url = AttendanceEmail.makeMailtoURL(
            to: ["teacher@school.edu", "admin@school.edu"],
            subject: "Attendance • Jan 15, 2025",
            body: "Test body content"
        )

        #expect(url != nil)
        if let url = url {
            #expect(url.scheme == "mailto")
            assertTextSnapshot(url.absoluteString, named: "mailtoURL")
        }
    }

    // MARK: - Recipient Parsing Tests

    @Test("Parse recipients comma delimited")
    func parseRecipients_commaDelimited() {
        let result = AttendanceEmail.parseRecipients(from: "a@test.com, b@test.com, c@test.com")
        let output = result.joined(separator: "\n")

        #expect(result.count == 3)
        #expect(result.contains("a@test.com"))
        assertTextSnapshot(output, named: "commaDelimited")
    }

    @Test("Parse recipients semicolon delimited")
    func parseRecipients_semicolonDelimited() {
        let result = AttendanceEmail.parseRecipients(from: "a@test.com; b@test.com; c@test.com")
        let output = result.joined(separator: "\n")

        #expect(result.count == 3)
        assertTextSnapshot(output, named: "semicolonDelimited")
    }

    @Test("Parse recipients mixed delimiters")
    func parseRecipients_mixedDelimiters() {
        let result = AttendanceEmail.parseRecipients(from: "a@test.com, b@test.com; c@test.com")
        let output = result.joined(separator: "\n")

        #expect(result.count == 3)
        assertTextSnapshot(output, named: "mixedDelimiters")
    }

    @Test("Parse recipients with whitespace")
    func parseRecipients_withWhitespace() {
        let result = AttendanceEmail.parseRecipients(from: "  a@test.com  ,  b@test.com  ")
        let output = result.joined(separator: "\n")

        #expect(result.count == 2)
        #expect(result.first == "a@test.com")
        assertTextSnapshot(output, named: "withWhitespace")
    }

    @Test("Parse recipients empty string")
    func parseRecipients_emptyString() {
        let result = AttendanceEmail.parseRecipients(from: "")
        #expect(result.isEmpty)
    }

    @Test("Parse recipients nil input")
    func parseRecipients_nilInput() {
        let result = AttendanceEmail.parseRecipients(from: nil)
        #expect(result.isEmpty)
    }
}

#endif
