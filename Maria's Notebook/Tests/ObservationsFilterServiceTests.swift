#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Test Helpers

@MainActor
private func makeTestObservationItem(
    id: UUID = UUID(),
    date: Date = Date(),
    body: String = "Test observation",
    category: NoteCategory = .general,
    includeInReport: Bool = false,
    imagePath: String? = nil,
    contextText: String? = nil,
    studentIDs: [UUID] = [],
    context: ModelContext
) -> UnifiedObservationItem {
    // Create a backing Note for the source
    let note = Note(body: body, scope: studentIDs.isEmpty ? .all : (studentIDs.count == 1 ? .student(studentIDs[0]) : .students(studentIDs)), category: category, includeInReport: includeInReport)
    context.insert(note)

    return UnifiedObservationItem(
        id: id,
        date: date,
        body: body,
        category: category,
        includeInReport: includeInReport,
        imagePath: imagePath,
        contextText: contextText,
        studentIDs: studentIDs,
        source: .note(note)
    )
}

// MARK: - ObservationsFilterService Category Filter Tests

@Suite("ObservationsFilterService Category Filter Tests", .serialized)
@MainActor
struct ObservationsFilterServiceCategoryTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    @Test("filter returns all items when category is nil")
    func filterReturnsAllWhenCategoryNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(category: .academic, context: context)
        let item2 = makeTestObservationItem(category: .behavioral, context: context)
        let item3 = makeTestObservationItem(category: .general, context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2, item3],
            category: nil,
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 3)
    }

    @Test("filter returns only matching category items")
    func filterReturnsMatchingCategory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let academic1 = makeTestObservationItem(body: "Academic 1", category: .academic, context: context)
        let academic2 = makeTestObservationItem(body: "Academic 2", category: .academic, context: context)
        let behavioral = makeTestObservationItem(body: "Behavioral", category: .behavioral, context: context)

        let result = ObservationsFilterService.filter(
            items: [academic1, academic2, behavioral],
            category: .academic,
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.category == .academic })
    }

    @Test("filter returns empty when no items match category")
    func filterReturnsEmptyWhenNoMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(category: .academic, context: context)
        let item2 = makeTestObservationItem(category: .behavioral, context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            category: .health,
            scope: .all,
            searchText: ""
        )

        #expect(result.isEmpty)
    }
}

// MARK: - ObservationsFilterService Scope Filter Tests

@Suite("ObservationsFilterService Scope Filter Tests", .serialized)
@MainActor
struct ObservationsFilterServiceScopeTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    @Test("filter with scope all returns all items")
    func filterScopeAllReturnsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let studentSpecific = makeTestObservationItem(body: "Student specific", studentIDs: [studentID], context: context)
        let allStudents = makeTestObservationItem(body: "All students", studentIDs: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [studentSpecific, allStudents],
            category: nil,
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 2)
    }

    @Test("filter with scope studentSpecific returns only items with studentIDs")
    func filterScopeStudentSpecific() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let studentSpecific = makeTestObservationItem(body: "Student specific", studentIDs: [studentID], context: context)
        let allStudents = makeTestObservationItem(body: "All students", studentIDs: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [studentSpecific, allStudents],
            category: nil,
            scope: .studentSpecific,
            searchText: ""
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Student specific")
    }

    @Test("filter with scope allStudents returns only items without studentIDs")
    func filterScopeAllStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let studentSpecific = makeTestObservationItem(body: "Student specific", studentIDs: [studentID], context: context)
        let allStudents = makeTestObservationItem(body: "All students", studentIDs: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [studentSpecific, allStudents],
            category: nil,
            scope: .allStudents,
            searchText: ""
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "All students")
    }

    @Test("filter with scope studentSpecific handles multiple students")
    func filterScopeStudentSpecificMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = UUID()
        let student2 = UUID()
        let multiStudent = makeTestObservationItem(body: "Multi student", studentIDs: [student1, student2], context: context)
        let allStudents = makeTestObservationItem(body: "All students", studentIDs: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [multiStudent, allStudents],
            category: nil,
            scope: .studentSpecific,
            searchText: ""
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Multi student")
    }
}

// MARK: - ObservationsFilterService Search Text Tests

@Suite("ObservationsFilterService Search Text Tests", .serialized)
@MainActor
struct ObservationsFilterServiceSearchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    @Test("filter with empty search text returns all items")
    func filterEmptySearchReturnsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(body: "First observation", context: context)
        let item2 = makeTestObservationItem(body: "Second observation", context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            category: nil,
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 2)
    }

    @Test("filter with whitespace-only search text returns all items")
    func filterWhitespaceSearchReturnsAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(body: "First observation", context: context)
        let item2 = makeTestObservationItem(body: "Second observation", context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            category: nil,
            scope: .all,
            searchText: "   "
        )

        #expect(result.count == 2)
    }

    @Test("filter with search text matches case insensitively")
    func filterSearchCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(body: "UPPERCASE observation", context: context)
        let item2 = makeTestObservationItem(body: "lowercase observation", context: context)
        let item3 = makeTestObservationItem(body: "MixedCase observation", context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2, item3],
            category: nil,
            scope: .all,
            searchText: "observation"
        )

        #expect(result.count == 3)
    }

    @Test("filter with search text matches partial words")
    func filterSearchPartialMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(body: "Academic progress noted", context: context)
        let item2 = makeTestObservationItem(body: "Behavioral observation", context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            category: nil,
            scope: .all,
            searchText: "acad"
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Academic progress noted")
    }

    @Test("filter with search text returns empty when no match")
    func filterSearchNoMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(body: "First observation", context: context)
        let item2 = makeTestObservationItem(body: "Second observation", context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            category: nil,
            scope: .all,
            searchText: "xyz123"
        )

        #expect(result.isEmpty)
    }
}

// MARK: - ObservationsFilterService Combined Filter Tests

@Suite("ObservationsFilterService Combined Filter Tests", .serialized)
@MainActor
struct ObservationsFilterServiceCombinedTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    @Test("filter combines category and scope filters")
    func filterCombinesCategoryAndScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let academicStudent = makeTestObservationItem(body: "Academic student", category: .academic, studentIDs: [studentID], context: context)
        let academicAll = makeTestObservationItem(body: "Academic all", category: .academic, studentIDs: [], context: context)
        let behavioralStudent = makeTestObservationItem(body: "Behavioral student", category: .behavioral, studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [academicStudent, academicAll, behavioralStudent],
            category: .academic,
            scope: .studentSpecific,
            searchText: ""
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Academic student")
    }

    @Test("filter combines category and search text")
    func filterCombinesCategoryAndSearch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let academicMath = makeTestObservationItem(body: "Math progress excellent", category: .academic, context: context)
        let academicReading = makeTestObservationItem(body: "Reading needs work", category: .academic, context: context)
        let behavioralMath = makeTestObservationItem(body: "Math behavior issues", category: .behavioral, context: context)

        let result = ObservationsFilterService.filter(
            items: [academicMath, academicReading, behavioralMath],
            category: .academic,
            scope: .all,
            searchText: "math"
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Math progress excellent")
    }

    @Test("filter combines scope and search text")
    func filterCombinesScopeAndSearch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let studentMath = makeTestObservationItem(body: "Math student", studentIDs: [studentID], context: context)
        let studentReading = makeTestObservationItem(body: "Reading student", studentIDs: [studentID], context: context)
        let allMath = makeTestObservationItem(body: "Math all", studentIDs: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [studentMath, studentReading, allMath],
            category: nil,
            scope: .studentSpecific,
            searchText: "math"
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Math student")
    }

    @Test("filter combines all three filters")
    func filterCombinesAllThree() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        // Create various combinations
        let target = makeTestObservationItem(body: "Math academic student", category: .academic, studentIDs: [studentID], context: context)
        let wrongCategory = makeTestObservationItem(body: "Math behavioral student", category: .behavioral, studentIDs: [studentID], context: context)
        let wrongScope = makeTestObservationItem(body: "Math academic all", category: .academic, studentIDs: [], context: context)
        let wrongSearch = makeTestObservationItem(body: "Reading academic student", category: .academic, studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [target, wrongCategory, wrongScope, wrongSearch],
            category: .academic,
            scope: .studentSpecific,
            searchText: "math"
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Math academic student")
    }

    @Test("filter returns empty when all filters exclude everything")
    func filterReturnsEmptyWhenAllExclude() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let item = makeTestObservationItem(body: "Reading behavioral student", category: .behavioral, studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [item],
            category: .academic,
            scope: .allStudents,
            searchText: "math"
        )

        #expect(result.isEmpty)
    }
}

// MARK: - ObservationsFilterService Edge Cases

@Suite("ObservationsFilterService Edge Cases", .serialized)
@MainActor
struct ObservationsFilterServiceEdgeCaseTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    @Test("filter handles empty items array")
    func filterHandlesEmptyArray() {
        let result = ObservationsFilterService.filter(
            items: [],
            category: .academic,
            scope: .studentSpecific,
            searchText: "test"
        )

        #expect(result.isEmpty)
    }

    @Test("filter handles special characters in search text")
    func filterHandlesSpecialCharacters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = makeTestObservationItem(body: "Test (with) [special] characters!", context: context)

        let result = ObservationsFilterService.filter(
            items: [item],
            category: nil,
            scope: .all,
            searchText: "(with)"
        )

        #expect(result.count == 1)
    }

    @Test("filter handles unicode in search text")
    func filterHandlesUnicode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = makeTestObservationItem(body: "Student learned about caf\u{00E9} culture", context: context)

        let result = ObservationsFilterService.filter(
            items: [item],
            category: nil,
            scope: .all,
            searchText: "caf\u{00E9}"
        )

        #expect(result.count == 1)
    }
}

#endif
