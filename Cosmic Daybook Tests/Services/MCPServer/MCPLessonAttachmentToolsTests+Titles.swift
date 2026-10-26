import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `attach_file_to_lesson` matches titles as written (review of 2026-10-25,
/// finding 1): a title the name on disk can't tell apart from another is
/// still another file, not a clash and not a record to replace.
extension MCPLessonAttachmentToolsTests {

    @Test("A title that differs only in a fraction attaches a second file; replace_existing replaces only its own")
    func titlesDifferingInAFraction() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let half = try fixture.write(LessonFileToolFixture.pdf(0.1), named: "half.pdf")
        let quarter = try fixture.write(LessonFileToolFixture.pdf(0.2), named: "quarter.pdf")
        let newHalf = try fixture.write(LessonFileToolFixture.pdf(0.3), named: "half-v2.pdf")

        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(half.path, title: "Fractions ½"))
        // Not refused as the same title.
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(quarter.path, title: "Fractions ¼"))
        let attached = try fixture.stored()
        #expect(attached.map(\.title) == ["Fractions ½", "Fractions ¼"])

        let receipt = try await fixture.call(
            "attach_file_to_lesson", fixture.attach(newHalf.path, title: "Fractions ½", replace: true)
        )
        #expect(receipt.hasPrefix("Replaced 'Fractions ½'"))

        let after = try fixture.stored()
        #expect(after.map(\.id) == attached.map(\.id), "still the same two files")
        let byTitle = Dictionary(uniqueKeysWithValues: after.map { ($0.title, $0) })
        let replacedHalf = try #require(byTitle["Fractions ½"])
        let keptQuarter = try #require(byTitle["Fractions ¼"])
        #expect(try fixture.bytes(of: replacedHalf) == Data(contentsOf: newHalf))
        #expect(try fixture.bytes(of: keptQuarter) == Data(contentsOf: quarter), "the ¼ file is untouched")
        #expect(keptQuarter.path == attached[1].path)
    }
}
