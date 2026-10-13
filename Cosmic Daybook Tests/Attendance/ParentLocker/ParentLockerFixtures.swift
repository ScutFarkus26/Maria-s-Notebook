import Foundation
import Testing
@testable import CosmicDaybook

/// Recorded-shape ParentLocker replies with made-up children, classes and ids
/// (`Fixtures/ParentLocker-*`), shaped like the real ones read 2026-10-12:
/// - `page.html`: the attendance page, its course lists on one script line
///   each (two classes, a third in `additional_courses`, the first repeated).
/// - `signin.html` and `changed.html`: the sign-in page, and a page that is neither.
/// - `roster-middle.json`, Girls Middle School: Wren Halloway, Juniper Ashby
///   (alternate name June), Marisol Peña (Present, saved, with a note), two
///   children both named Ada Fern, Tamsin Okafor (Absent, locked by the
///   office) and Pippa Lindqvist.
/// - `roster-upper.json`, Upper Elementary Girls: Wren Calloway, Odile Brandt
///   (Present, saved), Saoirse Quill (Present only as expected) and Bea
///   Marchetti (Late, saved).
/// - `save-reply.json` (two conflicts, one already equal) and `save-refused.json`.
/// The marks are Present 701, Late 702 and Absent 703, plus a deleted Absent
/// (699) and a hidden Late (704).
enum ParentLockerFixtures {

    private final class BundleToken {}

    static let host = "school.parentlocker.test"

    static let middleSchool = ParentLockerCourse(
        courseID: 5101, name: "Girls Middle School", period: 1, attendanceReportID: "880001"
    )
    static let upperElementary = ParentLockerCourse(
        courseID: 5102, name: "Upper Elementary Girls", period: 1, attendanceReportID: "880002"
    )

    /// A fixture file's bytes, by its name after `ParentLocker-`.
    static func data(_ name: String) throws -> Data {
        let parts = name.split(separator: ".")
        let url = try #require(Bundle(for: BundleToken.self).url(
            forResource: "ParentLocker-\(parts[0])", withExtension: String(parts[1])
        ))
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        try #require(String(bytes: data(name), encoding: .utf8))
    }

    static func json(_ name: String) throws -> ParentLockerJSON {
        try JSONDecoder().decode(ParentLockerJSON.self, from: data(name))
    }

    /// Both classes' rosters, as the transport reads them.
    static func rosters() throws -> [ParentLockerRoster] {
        [
            try ParentLockerRoster(reply: json("roster-middle.json"), course: middleSchool),
            try ParentLockerRoster(reply: json("roster-upper.json"), course: upperElementary)
        ]
    }
}
