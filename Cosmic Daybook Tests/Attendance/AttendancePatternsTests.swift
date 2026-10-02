import Foundation
import Testing
@testable import CosmicDaybook

/// Patterns gathers siblings into one family, since one conversation with
/// a family covers all of its children.
struct AttendancePatternsTests {

    private func entry(_ name: String, absent: Int = 0, late: Int = 0) -> AttendanceWatchListEntry {
        let id = UUID()
        return AttendanceWatchListEntry(
            id: id, studentID: id, fullName: name, absentCount: absent, tardyCount: late, recentPattern: []
        )
    }

    @Test("Two or more of a family on the list become one family line, counted together")
    func familyGathered() {
        let toba = entry("Toba Fox", absent: 1, late: 5)
        let leora = entry("Leora Fox", absent: 1, late: 3)
        let ada = entry("Ada Green", late: 2)
        let solo = entry("Uma Pine", absent: 1)
        let keys = [toba.studentID: "name:fox", leora.studentID: "name:fox",
                    ada.studentID: "name:green", solo.studentID: "name:pine"]
        let patterns = AttendanceInsightsService.patterns(
            [ada, leora, solo, toba], familyKey: { keys[$0] }, familyName: { _ in "Fox" }, limit: 5
        )
        #expect(patterns.count == 3)
        let family = patterns[0]
        #expect(family.familyName == "Fox")
        #expect(family.members.map(\.fullName) == ["Toba Fox", "Leora Fox"])
        #expect(family.tardyCount == 8 && family.absentCount == 2)
        #expect(patterns.dropFirst().allSatisfy { $0.familyName == nil && $0.members.count == 1 })
    }

    @Test("A family counts once against the limit")
    func familyCountsOnce() {
        let kids = (0..<4).map { entry("Kid\($0) Fox", late: 3) }
        let others = (0..<4).map { entry("Other\($0)", late: 1) }
        let keys = Dictionary(uniqueKeysWithValues: kids.map { ($0.studentID, "name:fox") })
        let patterns = AttendanceInsightsService.patterns(
            kids + others, familyKey: { keys[$0] }, familyName: { _ in "Fox" }, limit: 3
        )
        #expect(patterns.count == 3)
        #expect(patterns[0].members.count == 4)
    }
}
