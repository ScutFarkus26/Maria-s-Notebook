#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("NoteTemplateRepository Fetch Tests", .serialized)
@MainActor
struct NoteTemplateRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NoteTemplate.self,
        ])
    }

    @Test("fetchTemplate returns template by ID")
    func fetchTemplateReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Test Template", body: "Template body")
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchTemplate(id: template.id)

        #expect(fetched != nil)
        #expect(fetched?.id == template.id)
        #expect(fetched?.title == "Test Template")
    }

    @Test("fetchTemplate returns nil for missing ID")
    func fetchTemplateReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchTemplate(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchTemplates returns all when no predicate")
    func fetchTemplatesReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template1 = NoteTemplate(title: "Template 1", body: "Body 1")
        let template2 = NoteTemplate(title: "Template 2", body: "Body 2")
        let template3 = NoteTemplate(title: "Template 3", body: "Body 3")
        context.insert(template1)
        context.insert(template2)
        context.insert(template3)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchTemplates()

        #expect(fetched.count == 3)
    }

    @Test("fetchTemplates sorts by sortOrder by default")
    func fetchTemplatesSortsBySortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template1 = NoteTemplate(title: "Third", body: "Body", sortOrder: 3)
        let template2 = NoteTemplate(title: "First", body: "Body", sortOrder: 1)
        let template3 = NoteTemplate(title: "Second", body: "Body", sortOrder: 2)
        context.insert(template1)
        context.insert(template2)
        context.insert(template3)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchTemplates()

        #expect(fetched[0].title == "First")
        #expect(fetched[1].title == "Second")
        #expect(fetched[2].title == "Third")
    }

    @Test("fetchBuiltInTemplates returns built-in only")
    func fetchBuiltInTemplatesReturnsBuiltInOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let builtIn = NoteTemplate(title: "Built-in", body: "Body", isBuiltIn: true)
        let custom = NoteTemplate(title: "Custom", body: "Body", isBuiltIn: false)
        context.insert(builtIn)
        context.insert(custom)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchBuiltInTemplates()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Built-in")
        #expect(fetched[0].isBuiltIn == true)
    }

    @Test("fetchCustomTemplates returns custom only")
    func fetchCustomTemplatesReturnsCustomOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let builtIn = NoteTemplate(title: "Built-in", body: "Body", isBuiltIn: true)
        let custom = NoteTemplate(title: "Custom", body: "Body", isBuiltIn: false)
        context.insert(builtIn)
        context.insert(custom)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchCustomTemplates()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Custom")
        #expect(fetched[0].isBuiltIn == false)
    }

    @Test("fetchTemplates handles empty database")
    func fetchTemplatesHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let fetched = repository.fetchTemplates()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("NoteTemplateRepository Create Tests", .serialized)
@MainActor
struct NoteTemplateRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NoteTemplate.self,
        ])
    }

    @Test("createTemplate creates template with required fields")
    func createTemplateCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let template = repository.createTemplate(
            title: "Test Template",
            body: "This is the template body"
        )

        #expect(template.title == "Test Template")
        #expect(template.body == "This is the template body")
        #expect(template.isBuiltIn == false) // Custom templates are never built-in
    }

    @Test("createTemplate sets optional fields when provided")
    func createTemplateSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let behavioralTag = TagHelper.tagFromNoteCategory("behavioral")
        let template = repository.createTemplate(
            title: "Observation",
            body: "The student demonstrated...",
            tags: [behavioralTag],
            sortOrder: 50
        )

        #expect(template.tags == [behavioralTag])
        #expect(template.sortOrder == 50)
    }

    @Test("createTemplate auto-calculates sortOrder after existing templates")
    func createTemplateAutoCalculatesSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = NoteTemplate(title: "Existing", body: "Body", sortOrder: 105, isBuiltIn: false)
        context.insert(existing)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let template = repository.createTemplate(title: "New", body: "Body")

        #expect(template.sortOrder == 106) // After existing custom template
    }

    @Test("createTemplate persists to context")
    func createTemplatePersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let template = repository.createTemplate(title: "Test", body: "Body")

        let fetched = repository.fetchTemplate(id: template.id)

        #expect(fetched != nil)
        #expect(fetched?.id == template.id)
    }
}

// MARK: - Update Tests

@Suite("NoteTemplateRepository Update Tests", .serialized)
@MainActor
struct NoteTemplateRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NoteTemplate.self,
        ])
    }

    @Test("updateTemplate updates title")
    func updateTemplateUpdatesTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Original Title", body: "Body", isBuiltIn: false)
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: template.id, title: "Updated Title")

        #expect(result == true)
        #expect(template.title == "Updated Title")
    }

    @Test("updateTemplate updates body")
    func updateTemplateUpdatesBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Test", body: "Original body", isBuiltIn: false)
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: template.id, body: "Updated body")

        #expect(result == true)
        #expect(template.body == "Updated body")
    }

    @Test("updateTemplate updates tags")
    func updateTemplateUpdatesTags() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Test", body: "Body", isBuiltIn: false)
        context.insert(template)
        try context.save()

        let behavioralTag = TagHelper.tagFromNoteCategory("behavioral")
        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: template.id, tags: [behavioralTag])

        #expect(result == true)
        #expect(template.tags == [behavioralTag])
    }

    @Test("updateTemplate updates sortOrder")
    func updateTemplateUpdatesSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Test", body: "Body", sortOrder: 100, isBuiltIn: false)
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: template.id, sortOrder: 50)

        #expect(result == true)
        #expect(template.sortOrder == 50)
    }

    @Test("updateTemplate returns false for missing ID")
    func updateTemplateReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: UUID(), title: "New Title")

        #expect(result == false)
    }

    @Test("updateTemplate returns false for built-in template")
    func updateTemplateReturnsFalseForBuiltIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Built-in", body: "Body", isBuiltIn: true)
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        let result = repository.updateTemplate(id: template.id, title: "Modified")

        #expect(result == false)
        #expect(template.title == "Built-in") // Unchanged
    }

    @Test("updateTemplate only changes specified fields")
    func updateTemplateOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let behavioralTag = TagHelper.tagFromNoteCategory("behavioral")
        let template = NoteTemplate(title: "Original", body: "Original body", tags: [behavioralTag], isBuiltIn: false)
        context.insert(template)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        _ = repository.updateTemplate(id: template.id, title: "Updated")

        #expect(template.title == "Updated")
        #expect(template.body == "Original body") // Unchanged
        #expect(template.tags == [behavioralTag]) // Unchanged
    }
}

// MARK: - Reorder Tests

@Suite("NoteTemplateRepository Reorder Tests", .serialized)
@MainActor
struct NoteTemplateRepositoryReorderTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NoteTemplate.self,
        ])
    }

    @Test("reorderTemplates updates sort orders")
    func reorderTemplatesUpdatesSortOrders() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template1 = NoteTemplate(title: "First", body: "Body", sortOrder: 100, isBuiltIn: false)
        let template2 = NoteTemplate(title: "Second", body: "Body", sortOrder: 101, isBuiltIn: false)
        let template3 = NoteTemplate(title: "Third", body: "Body", sortOrder: 102, isBuiltIn: false)
        context.insert(template1)
        context.insert(template2)
        context.insert(template3)
        try context.save()

        // Reorder: Third, First, Second
        let repository = NoteTemplateRepository(context: context)
        let result = repository.reorderTemplates(ids: [template3.id, template1.id, template2.id])

        #expect(result == true)
        #expect(template3.sortOrder == 100)
        #expect(template1.sortOrder == 101)
        #expect(template2.sortOrder == 102)
    }

    @Test("reorderTemplates ignores built-in templates")
    func reorderTemplatesIgnoresBuiltIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let builtIn = NoteTemplate(title: "Built-in", body: "Body", sortOrder: 1, isBuiltIn: true)
        let custom = NoteTemplate(title: "Custom", body: "Body", sortOrder: 100, isBuiltIn: false)
        context.insert(builtIn)
        context.insert(custom)
        try context.save()

        let repository = NoteTemplateRepository(context: context)
        _ = repository.reorderTemplates(ids: [custom.id, builtIn.id])

        #expect(builtIn.sortOrder == 1) // Unchanged
        #expect(custom.sortOrder == 100) // Updated
    }
}

// MARK: - Delete Tests

@Suite("NoteTemplateRepository Delete Tests", .serialized)
@MainActor
struct NoteTemplateRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NoteTemplate.self,
        ])
    }

    @Test("deleteTemplate removes custom template from context")
    func deleteTemplateRemovesCustomFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Custom", body: "Body", isBuiltIn: false)
        context.insert(template)
        try context.save()

        let templateID = template.id

        let repository = NoteTemplateRepository(context: context)
        try repository.deleteTemplate(id: templateID)

        let fetched = repository.fetchTemplate(id: templateID)
        #expect(fetched == nil)
    }

    @Test("deleteTemplate does not delete built-in template")
    func deleteTemplateDoesNotDeleteBuiltIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let template = NoteTemplate(title: "Built-in", body: "Body", isBuiltIn: true)
        context.insert(template)
        try context.save()

        let templateID = template.id

        let repository = NoteTemplateRepository(context: context)
        try repository.deleteTemplate(id: templateID)

        let fetched = repository.fetchTemplate(id: templateID)
        #expect(fetched != nil) // Still exists
        #expect(fetched?.title == "Built-in")
    }

    @Test("deleteTemplate does nothing for missing ID")
    func deleteTemplateDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteTemplateRepository(context: context)
        try repository.deleteTemplate(id: UUID())

        // Should not throw
    }
}

#endif
