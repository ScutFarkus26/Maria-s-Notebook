import Foundation
import Testing
@testable import CosmicDaybook

/// The review of the afternoon fixes (plan "ParentLocker bug hunt afternoon
/// fixes", Phase 2), the notebook's words: a day ParentLocker isn't
/// expecting, on Send Now's toast and from the Shortcut, and the Shortcut's
/// reply after sending with children unmarked.
@Suite("Attendance screen and ParentLocker, fix round")
@MainActor
struct AttendanceParentLockerFixRoundScreenTests {

    typealias Screen = AttendanceExpandedView

    private static let notExpectedLine = "ParentLocker isn't expecting attendance today."

    private static func report(
        savedCount: Int, unmarked: [String] = [], notExpected: Bool = false
    ) -> ParentLockerReport {
        ParentLockerReport(
            day: ParentLockerTestDevice.morning, wasPreview: false, classes: [], problems: [],
            classesLeftAlone: [], savedCount: savedCount, unmarked: unmarked,
            waitsForMarks: !unmarked.isEmpty, notExpected: notExpected
        )
    }

    @Test("Send Now on a day ParentLocker isn't expecting says so, and not as a failure")
    func toastOnANotExpectedDay() {
        #expect(Screen.sendNowToast(for: ParentLockerStatus(state: .notExpected)) == .info(Self.notExpectedLine))
    }

    @Test("The Shortcut on a day ParentLocker isn't expecting says so, not that ParentLocker already has it")
    func shortcutOnANotExpectedDay() {
        #expect(SendAttendanceIntent.reply(to: .success(Self.report(savedCount: 0, notExpected: true)))
            == Self.notExpectedLine)
    }

    @Test("After sending with children unmarked, the Shortcut names them and says the day isn't recorded as sent")
    func shortcutNamesTheUnmarked() {
        #expect(SendAttendanceIntent.reply(to: .success(Self.report(savedCount: 4, unmarked: ["Bea M"])))
            == "Sent today's attendance to ParentLocker: 4 children updated. "
                + "Bea M isn't marked yet, so today isn't recorded as sent.")
        #expect(SendAttendanceIntent.reply(to: .success(Self.report(savedCount: 0, unmarked: ["Bea M", "Wren H"])))
            == "ParentLocker already has everyone who's marked. "
                + "Bea M and Wren H aren't marked yet, so today isn't recorded as sent.")
        let many = ["Ari C", "Bea M", "June A", "Wren H"]
        #expect(SendAttendanceIntent.reply(to: .success(Self.report(savedCount: 1, unmarked: many)))
            == "Sent today's attendance to ParentLocker: 1 child updated. "
                + "4 children aren't marked yet, so today isn't recorded as sent.")
        #expect(SendAttendanceIntent.reply(to: .success(Self.report(savedCount: 0)))
            == "ParentLocker already has today's attendance.", "everyone marked: as before")
    }
}
