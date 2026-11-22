import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 6: one lesson picker serves every screen that links
/// lessons. (The Files section's linked Resources files, and their tests, went
/// with Resources on 2026-11-22.)
@Suite("Lessons: one Files section and one lesson picker (simplify phase 6)")
@MainActor
struct LessonFilesSectionTests {

    @Test("The lesson picker groups by area in catalog order and searches name, area and sequence")
    func pickerGroupsAndSearches() throws {
        let context = try CoreDataTestHelpers.makeContext()
        func lesson(_ name: String, area: String, sequence: String) -> CDLesson {
            let lesson = CDLesson(context: context)
            lesson.name = name
            lesson.area = area
            lesson.sequence = sequence
            return lesson
        }
        let lessons = [
            lesson("Golden Beads", area: "Math", sequence: "Decimal System"),
            lesson("Noun Family", area: "Language ", sequence: "Grammar"),
            lesson("Stamp Game", area: "Math", sequence: "Decimal System"),
            lesson("Parts of the Leaf", area: "Botany", sequence: "Leaf")
        ]

        let all = LessonLinkPickerGroup.groups(from: lessons, matching: "")
        #expect(all.map(\.area) == ["Math", "Language", "Botany"])
        #expect(all[0].lessons.map(\.name) == ["Golden Beads", "Stamp Game"])

        let bySequence = LessonLinkPickerGroup.groups(from: lessons, matching: "decimal")
        #expect(bySequence.flatMap(\.lessons).map(\.name) == ["Golden Beads", "Stamp Game"])
        let byArea = LessonLinkPickerGroup.groups(from: lessons, matching: "botany")
        #expect(byArea.flatMap(\.lessons).map(\.name) == ["Parts of the Leaf"])
    }
}
