import Foundation
import Testing
@testable import CosmicDaybook

/// Logs' pieces now live in the screens they repeated (plan "Simplify the
/// app", Phase 2): Meetings' History, Attendance's List, and a History choice
/// in each half of Lessons & Work. These pin the choices' names, what a saved
/// value resolves to, and where a route to a finished record lands.
@Suite("Logs folded into their screens")
@MainActor
struct LogsFoldedViewsTests {

    // MARK: - Lessons & Work

    @Test("Each half names its live list in its own words; both call the other History")
    func workspaceListTitles() {
        #expect(WorkspaceList.open.title(in: .presentations) == "Upcoming")
        #expect(WorkspaceList.open.title(in: .work) == "Open")
        #expect(WorkspaceList.history.title(in: .presentations) == "History")
        #expect(WorkspaceList.history.title(in: .work) == "History")
    }

    @Test("History searches with its own prompt; the live list keeps the half's")
    func workspaceListSearchPrompts() {
        for kind in WorkspaceKind.allCases {
            #expect(WorkspaceList.open.searchPrompt(in: kind) == kind.searchPrompt)
            #expect(WorkspaceList.history.searchPrompt(in: kind) != kind.searchPrompt)
        }
    }

    @Test(
        "Only a finished record's route opens History",
        arguments: [
            (TriageBucket.attention, WorkspaceList.open),
            (TriageBucket.scheduled, WorkspaceList.open),
            (TriageBucket.toSchedule, WorkspaceList.open),
            (TriageBucket.done, WorkspaceList.history)
        ]
    )
    func routeChoosesTheList(bucket: TriageBucket, expected: WorkspaceList) {
        #expect(WorkspaceList.holding(bucket) == expected)
    }

    @Test("A saved list choice round-trips, and a missing or unknown one is the live list")
    func workspaceListResolves() {
        for list in WorkspaceList.allCases {
            #expect(WorkspaceList.resolved(rawValue: list.rawValue) == list)
        }
        #expect(WorkspaceList.resolved(rawValue: nil) == .open)
        #expect(WorkspaceList.resolved(rawValue: "logs") == .open)
    }

    // MARK: - Meetings and Attendance

    @Test("Meetings has a Queue and a History, and opens on the queue")
    func meetingsViews() {
        #expect(MeetingsScreenView.allCases.map(\.title) == ["Queue", "History"])
        #expect(MeetingsScreenView.resolved(rawValue: "history") == .history)
        #expect(MeetingsScreenView.resolved(rawValue: nil) == .queue)
        #expect(MeetingsScreenView.resolved(rawValue: "meetings") == .queue)
    }

    @Test("Attendance has a Roll and a List, and opens on the roll")
    func attendanceViews() {
        #expect(AttendanceScreenView.allCases.map(\.title) == ["Roll", "List"])
        #expect(AttendanceScreenView.resolved(rawValue: "list") == .list)
        #expect(AttendanceScreenView.resolved(rawValue: nil) == .roll)
        #expect(AttendanceScreenView.resolved(rawValue: "attendance") == .roll)
    }

    @Test("The two screens' saved views are kept under keys of their own, apart from Logs'")
    func screenViewKeysAreTheirOwn() {
        let keys = [UserDefaultsKeys.meetingsScreenView, UserDefaultsKeys.attendanceScreenView]
        #expect(Set(keys).count == 2)
        #expect(!keys.contains(UserDefaultsKeys.logsMenuRootViewMode))
    }
}
