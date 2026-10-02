import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Todo Tag Display Name")
@MainActor
struct TodoTagDisplayNameTests {

    @Test("A student tag shows the canonical short name")
    func studentTagShowsShortName() {
        let tag = TodoTagHelper.createStudentTag(name: "Naomi Fisher")
        #expect(TodoTagHelper.displayName(tag) == "Naomi F")
        #expect(TodoTagHelper.displayName("Students/Naomi Fisher") == "Naomi F")
    }

    @Test("A two-word first name keeps both words")
    func twoWordFirstName() {
        #expect(TodoTagHelper.displayName("Students/Mary Kate Ross|Green") == "Mary Kate R")
    }

    @Test("A student with one name shows it whole")
    func singleName() {
        #expect(TodoTagHelper.displayName("Students/Naomi|Green") == "Naomi")
    }

    @Test("The roster's short name wins over the split, so a two-word last name comes out right")
    func rosterResolvesTwoWordLastName() {
        let roster = ["Ana De Leon": "Ana D"]
        #expect(TodoTagHelper.displayName("Students/Ana De Leon|Green", studentShortNames: roster) == "Ana D")
        #expect(TodoTagHelper.displayName("Students/Ana De Leon|Green") == "Ana De L")
        #expect(TodoTagHelper.displayName("Students/Naomi Fisher|Green", studentShortNames: roster) == "Naomi F")
    }

    @Test("Today's todo rows resolve student tags through the roster map, by exact full name")
    func rosterMapMatchesExactFullName() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "De Leon")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana Maria", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        // What `TodoTodayRow` is handed: the store's map, not a fetch per draw.
        let names = RosterStore(context: context).shortNamesByFullName

        #expect(TodoTagHelper.displayName("Students/Ana De Leon|Green", studentShortNames: names) == "Ana D")
        #expect(TodoTagHelper.displayName("Students/Ana Maria Soto|Green", studentShortNames: names) == "Ana Maria S")
        #expect(TodoTagHelper.displayName("Students/Ana Lopez|Green", studentShortNames: names) == "Ana L")
        #expect(TodoTagHelper.displayName("Urgent|Red", studentShortNames: names) == "Urgent")
    }

    @Test("The roster store files each child's short name under her tag's full name")
    func rosterStoreShortNames() throws {
        let context = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "De Leon")
        CoreDataTestHelpers.save(context)
        let roster = RosterStore(context: context)
        let tag = TodoTagHelper.syncStudentTags(existingTags: [], studentNames: ["Ana De Leon"])[0]
        #expect(TodoTagHelper.displayName(tag, studentShortNames: roster.shortNamesByFullName) == "Ana D")
    }

    @Test("Other tags, and the bare Students folder, are unchanged")
    func otherTagsUnchanged() {
        #expect(TodoTagHelper.displayName("Urgent|Red") == "Urgent")
        #expect(TodoTagHelper.displayName("Planning/Fall Term|Blue") == "Planning/Fall Term")
        #expect(TodoTagHelper.displayName("Students|Green") == "Students")
    }

    @Test("The raw tag name, used for filtering and storage, is untouched")
    func rawNameUntouched() {
        let tag = TodoTagHelper.createStudentTag(name: "Naomi Fisher")
        #expect(TodoTagHelper.tagName(tag) == "Students/Naomi Fisher")
        #expect(TodoTagHelper.leafTagName(tag) == "Naomi Fisher")
        let synced = TodoTagHelper.syncStudentTags(existingTags: [], studentNames: ["Naomi Fisher", "Naomi Ford"])
        #expect(synced.count == 2)
    }
}
