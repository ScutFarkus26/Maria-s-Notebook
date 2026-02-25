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
    tags: [String] = [],
    includeInReport: Bool = false,
    imagePath: String? = nil,
    contextText: String? = nil,
    studentIDs: [UUID] = [],
    context: ModelContext
) -> UnifiedObservationItem {
    // Create a backing Note for the source
    let note = Note(body: body, scope: studentIDs.isEmpty ? .all : (studentIDs.count == 1 ? .student(studentIDs[0]) : .students(studentIDs)), tags: tags, includeInReport: includeInReport)
    context.insert(note)

    return UnifiedObservationItem(
        id: id,
        date: date,
        body: body,
        tags: tags,
        includeInReport: includeInReport,
        imagePath: imagePath,
        contextText: contextText,
        studentIDs: studentIDs,
        source: .note(note)
    )
}

// MARK: - ObservationsFilterService Tag Filter Tests

@Suite("ObservationsFilterService Tag Filter Tests", .serialized)
@MainActor
struct ObservationsFilterServiceTagTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self])
    }

    private let academicTag = TagHelper.tagFromNoteCategory("academic")
    private let behavioralTag = TagHelper.tagFromNoteCategory("behavioral")
    private let healthTag = TagHelper.tagFromNoteCategory("health")

    @Test("filter returns all items when filterTags is empty")
    func filterReturnsAllWhenNoTags() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(tags: [academicTag], context: context)
        let item2 = makeTestObservationItem(tags: [behavioralTag], context: context)
        let item3 = makeTestObservationItem(tags: [], context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2, item3],
            filterTags: [],
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 3)
    }

    @Test("filter returns only matching tag items")
    func filterReturnsMatchingTag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let academic1 = makeTestObservationItem(body: "Academic 1", tags: [academicTag], context: context)
        let academic2 = makeTestObservationItem(body: "Academic 2", tags: [academicTag], context: context)
        let behavioral = makeTestObservationItem(body: "Behavioral", tags: [behavioralTag], context: context)

        let result = ObservationsFilterService.filter(
            items: [academic1, academic2, behavioral],
            filterTags: Set([academicTag]),
            scope: .all,
            searchText: ""
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.tags.contains(academicTag) })
    }

    @Test("filter returns empty when no items match tag")
    func filterReturnsEmptyWhenNoMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item1 = makeTestObservationItem(tags: [academicTag], context: context)
        let item2 = makeTestObservationItem(tags: [behavioralTag], context: context)

        let result = ObservationsFilterService.filter(
            items: [item1, item2],
            filterTags: Set([healthTag]),
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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
            filterTags: [],
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

    private let academicTag = TagHelper.tagFromNoteCategory("academic")
    private let behavioralTag = TagHelper.tagFromNoteCategory("behavioral")

    @Test("filter combines tags and scope filters")
    func filterCombinesTagsAndScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let academicStudent = makeTestObservationItem(body: "Academic student", tags: [academicTag], studentIDs: [studentID], context: context)
        let academicAll = makeTestObservationItem(body: "Academic all", tags: [academicTag], studentIDs: [], context: context)
        let behavioralStudent = makeTestObservationItem(body: "Behavioral student", tags: [behavioralTag], studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [academicStudent, academicAll, behavioralStudent],
            filterTags: Set([academicTag]),
            scope: .studentSpecific,
            searchText: ""
        )

        #expect(result.count == 1)
        #expect(result.first?.body == "Academic student")
    }

    @Test("filter combines tags and search text")
    func filterCombinesTagsAndSearch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let academicMath = makeTestObservationItem(body: "Math progress excellent", tags: [academicTag], context: context)
        let academicReading = makeTestObservationItem(body: "Reading needs work", tags: [academicTag], context: context)
        let behavioralMath = makeTestObservationItem(body: "Math behavior issues", tags: [behavioralTag], context: context)

        let result = ObservationsFilterService.filter(
            items: [academicMath, academicReading, behavioralMath],
            filterTags: Set([academicTag]),
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
            filterTags: [],
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
        let target = makeTestObservationItem(body: "Math academic student", tags: [academicTag], studentIDs: [studentID], context: context)
        let wrongTag = makeTestObservationItem(body: "Math behavioral student", tags: [behavioralTag], studentIDs: [studentID], context: context)
        let wrongScope = makeTestObservationItem(body: "Math academic all", tags: [academicTag], studentIDs: [], context: context)
        let wrongSearch = makeTestObservationItem(body: "Reading academic student", tags: [academicTag], studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [target, wrongTag, wrongScope, wrongSearch],
            filterTags: Set([academicTag]),
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
        let item = makeTestObservationItem(body: "Reading behavioral student", tags: [behavioralTag], studentIDs: [studentID], context: context)

        let result = ObservationsFilterService.filter(
            items: [item],
            filterTags: Set([academicTag]),
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
            filterTags: Set([TagHelper.tagFromNoteCategory("academic")]),
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
            filterTags: [],
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
            filterTags: [],
            scope: .all,
            searchText: "caf\u{00E9}"
        )

        #expect(result.count == 1)
    }
}

#endif
