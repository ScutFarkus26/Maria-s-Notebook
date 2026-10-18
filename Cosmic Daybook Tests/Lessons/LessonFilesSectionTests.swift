import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 6: a lesson's one Files section lists its
/// attachments and the Resources files linked to it or its area (the old
/// Related Resources section), and one lesson picker serves Resources,
/// Going Out and Projects.
@Suite("Lessons: one Files section and one lesson picker (simplify phase 6)")
@MainActor
struct LessonFilesSectionTests {

    private func resource(
        _ title: String,
        lessons: [UUID] = [],
        areas: String = "",
        in context: NSManagedObjectContext
    ) -> CDResource {
        let resource = CDResource(context: context)
        resource.id = UUID()
        resource.title = title
        resource.linkedLessonIDs = lessons.map(\.uuidString).joined(separator: ",")
        resource.linkedAreas = areas
        return resource
    }

    @Test("Linked by the lesson or by its area (any case, trimmed); another lesson or area is left out")
    func linkedResourcesMatch() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        let byLesson = resource("Bead Frame Paper", lessons: [UUID(), lessonID], in: context)
        let byArea = resource("Math Chart", areas: "Language, math ", in: context)
        let otherLesson = resource("Other Lesson Sheet", lessons: [UUID()], in: context)
        let lookalikeArea = resource("Mathematics Guide", areas: "Mathematics", in: context)

        let matched = LessonLinkedResources.matching(
            [byLesson, byArea, otherLesson, lookalikeArea], lessonID: lessonID, area: " Math"
        )
        #expect(matched.map(\.title) == ["Bead Frame Paper", "Math Chart"])
    }

    @Test("A resource linked both ways is listed once")
    func listedOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        let both = resource("Bead Frame Paper", lessons: [lessonID], areas: "Math", in: context)

        let matched = LessonLinkedResources.matching([both, both], lessonID: lessonID, area: "Math")
        #expect(matched.count == 1)
    }

    @Test("The section's fetch finds the linked resources without reading every one")
    func fetchFindsCandidates() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lessonID = UUID()
        _ = resource("Bead Frame Paper", lessons: [lessonID], in: context)
        _ = resource("Math Chart", areas: "Math", in: context)
        _ = resource("Map Blank", areas: "Geography", in: context)
        try context.save()

        let request = LessonLinkedResources.fetchRequest(lessonID: lessonID, area: "math")
        let candidates = try context.fetch(request)
        #expect(candidates.map(\.title) == ["Bead Frame Paper", "Math Chart"])
        #expect(LessonLinkedResources.matching(candidates, lessonID: lessonID, area: "math").count == 2)

        let none = LessonLinkedResources.fetchRequest(lessonID: nil, area: "  ")
        #expect(try context.fetch(none).isEmpty)
    }

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

    @Test("Files: favorites, recents, category, tag and search narrow the list as the old library did")
    func filesFilters() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let paper = resource("Cursive Paper", in: context)
        paper.category = .writingPapers
        paper.isFavorite = true
        paper.tagsArray = ["Handwriting"]
        let chart = resource("Hundred Chart", in: context)
        chart.category = .math
        chart.lastViewedAt = Date()
        let form = resource("Field Trip Form", in: context)
        form.category = .formsTemplates
        form.descriptionText = "permission slip"
        let all = [paper, chart, form]

        #expect(ResourceLibraryFilter().apply(to: all).count == 3)
        #expect(ResourceLibraryFilter(smartFilter: .favorites).apply(to: all) == [paper])
        #expect(ResourceLibraryFilter(smartFilter: .recents).apply(to: all) == [chart])
        #expect(ResourceLibraryFilter(category: .math).apply(to: all) == [chart])
        #expect(ResourceLibraryFilter(tag: "handwriting").apply(to: all) == [paper])
        #expect(ResourceLibraryFilter(searchText: "slip").apply(to: all) == [form])
    }
}
