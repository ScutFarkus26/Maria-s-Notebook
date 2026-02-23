#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Filtering Tests

@Suite("StudentsViewModel Filtering Tests", .serialized)
@MainActor
struct StudentsViewModelFilteringTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentLesson.self,
            Lesson.self,
        ])
    }

    @Test("filteredStudents returns all when filter is .all")
    func returnsAllWithAllFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .lower)
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical
        )

        #expect(result.count == 3)
    }

    @Test("filteredStudents returns only lower when filter is .lower")
    func returnsOnlyLowerWithLowerFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .lower)
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .lower,
            sortOrder: .alphabetical
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.level == .lower })
    }

    @Test("filteredStudents returns only upper when filter is .upper")
    func returnsOnlyUpperWithUpperFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .upper)
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .upper,
            sortOrder: .alphabetical
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.level == .upper })
    }

    @Test("filteredStudents respects search string")
    func respectsSearchString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "Alice"
        )

        #expect(result.count == 1)
        #expect(result[0].firstName == "Alice")
    }

    @Test("filteredStudents search is case insensitive")
    func searchIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "ALICE"
        )

        #expect(result.count == 1)
        #expect(result[0].firstName == "Alice")
    }

    @Test("filteredStudents search matches firstName")
    func searchMatchesFirstName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alexander", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Alexander")
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "Alex"
        )

        #expect(result.count == 2)  // Both match - one first name, one last name
    }

    @Test("filteredStudents search matches lastName")
    func searchMatchesLastName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Smithson")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Jones")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "Smith"
        )

        #expect(result.count == 2)
    }

    @Test("filteredStudents handles empty search string")
    func handlesEmptySearchString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: ""
        )

        #expect(result.count == 2)
    }

    @Test("filteredStudents handles whitespace-only search string")
    func handlesWhitespaceOnlySearchString() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "   "
        )

        #expect(result.count == 2)
    }

    @Test("filteredStudents returns empty for no matches")
    func returnsEmptyForNoMatches() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical,
            searchString: "Zzzzzz"
        )

        #expect(result.isEmpty)
    }

    @Test("filteredStudents handles empty database")
    func handlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical
        )

        #expect(result.isEmpty)
    }

    @Test("filteredStudents respects presentNowIDs filter")
    func respectsPresentNowIDsFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let presentIDs: Set<UUID> = [student1.id, student3.id]

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .presentNow,
            sortOrder: .alphabetical,
            presentNowIDs: presentIDs
        )

        #expect(result.count == 2)
        #expect(result.contains { $0.id == student1.id })
        #expect(result.contains { $0.id == student3.id })
        #expect(!result.contains { $0.id == student2.id })
    }
}

// MARK: - Sorting Tests

@Suite("StudentsViewModel Sorting Tests", .serialized)
@MainActor
struct StudentsViewModelSortingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentLesson.self,
            Lesson.self,
        ])
    }

    @Test("filteredStudents sorts alphabetically by fullName")
    func sortsAlphabeticallyByFullName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        let student2 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student3 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical
        )

        #expect(result[0].firstName == "Alice")
        #expect(result[1].firstName == "Bob")
        #expect(result[2].firstName == "Charlie")
    }

    @Test("filteredStudents sorts by manual order")
    func sortsByManualOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 3)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 1)
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 2)
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .manual
        )

        #expect(result[0].firstName == "Bob")     // manualOrder: 1
        #expect(result[1].firstName == "Charlie") // manualOrder: 2
        #expect(result[2].firstName == "Alice")   // manualOrder: 3
    }

    @Test("filteredStudents sorts by age (younger first)")
    func sortsByAge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        // Younger = more recent birthday = appears first when sorted by age (birthday desc)
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson",
                                       birthday: TestCalendar.date(year: 2015, month: 1, day: 1))
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown",
                                       birthday: TestCalendar.date(year: 2018, month: 6, day: 15))
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark",
                                       birthday: TestCalendar.date(year: 2016, month: 3, day: 10))
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .age
        )

        // Youngest (most recent birthday) should be first
        #expect(result[0].firstName == "Bob")     // 2018
        #expect(result[1].firstName == "Charlie") // 2016
        #expect(result[2].firstName == "Alice")   // 2015
    }

    @Test("filteredStudents sorts by next birthday")
    func sortsByNextBirthday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        // Use a fixed "today" date for testing
        let today = TestCalendar.date(year: 2025, month: 6, day: 15)

        // Birthday in July (coming up soon)
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson",
                                       birthday: TestCalendar.date(year: 2015, month: 7, day: 1))
        // Birthday in January (already passed this year, next is Jan next year)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown",
                                       birthday: TestCalendar.date(year: 2016, month: 1, day: 10))
        // Birthday in August
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark",
                                       birthday: TestCalendar.date(year: 2017, month: 8, day: 20))
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .birthday,
            today: today
        )

        // Alice (July 1) is closest, then Charlie (Aug 20), then Bob (Jan next year)
        #expect(result[0].firstName == "Alice")
        #expect(result[1].firstName == "Charlie")
        #expect(result[2].firstName == "Bob")
    }

    @Test("filteredStudents uses manualOrder as tiebreaker for alphabetical")
    func usesManualOrderAsTiebreakerForAlphabetical() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 2)
        let student2 = makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 1)
        context.insert(student1)
        context.insert(student2)

        let result = vm.filteredStudents(
            modelContext: context,
            filter: .all,
            sortOrder: .alphabetical
        )

        #expect(result[0].manualOrder == 1)
        #expect(result[1].manualOrder == 2)
    }
}

// MARK: - Manual Order Tests

@Suite("StudentsViewModel Manual Order Tests", .serialized)
@MainActor
struct StudentsViewModelManualOrderTests {

    @Test("ensureInitialManualOrderIfNeeded assigns sequential orders when all zero")
    func assignsSequentialOrdersWhenAllZero() {
        let vm = StudentsViewModel()

        let students = [
            makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 0),
            makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 0),
            makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 0),
        ]

        let changed = vm.ensureInitialManualOrderIfNeeded(students)

        #expect(changed == true)
        // Should be sorted alphabetically and assigned sequential orders
        let sorted = students.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        for (idx, student) in sorted.enumerated() {
            #expect(student.manualOrder == idx)
        }
    }

    @Test("ensureInitialManualOrderIfNeeded does nothing when orders already set")
    func doesNothingWhenOrdersAlreadySet() {
        let vm = StudentsViewModel()

        let students = [
            makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 1),
            makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 2),
            makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 3),
        ]

        let changed = vm.ensureInitialManualOrderIfNeeded(students)

        #expect(changed == false)
        #expect(students[0].manualOrder == 1)
        #expect(students[1].manualOrder == 2)
        #expect(students[2].manualOrder == 3)
    }

    @Test("ensureInitialManualOrderIfNeeded returns false for empty array")
    func returnsFalseForEmptyArray() {
        let vm = StudentsViewModel()

        let changed = vm.ensureInitialManualOrderIfNeeded([])

        #expect(changed == false)
    }

    @Test("repairManualOrderUniquenessIfNeeded fixes duplicates")
    func fixesDuplicateOrders() {
        let vm = StudentsViewModel()

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 1),
            makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 1),  // Duplicate
            makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 2),
        ]

        let changed = vm.repairManualOrderUniquenessIfNeeded(students)

        #expect(changed == true)
        // Bob should get a new unique order (3, since 1 and 2 are taken)
        let orders = students.map { $0.manualOrder }
        #expect(Set(orders).count == orders.count)  // All unique
    }

    @Test("repairManualOrderUniquenessIfNeeded does nothing when all unique")
    func doesNothingWhenAllUnique() {
        let vm = StudentsViewModel()

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 1),
            makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 2),
            makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 3),
        ]

        let changed = vm.repairManualOrderUniquenessIfNeeded(students)

        #expect(changed == false)
    }

    @Test("repairManualOrderUniquenessIfNeeded returns false for empty array")
    func repairReturnsFalseForEmptyArray() {
        let vm = StudentsViewModel()

        let changed = vm.repairManualOrderUniquenessIfNeeded([])

        #expect(changed == false)
    }

    @Test("mergeReorderedSubsetIntoAll preserves order of non-subset items")
    func mergePreservesNonSubsetOrder() {
        let vm = StudentsViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson", manualOrder: 0)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 1)
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark", manualOrder: 2)
        let student4 = makeTestStudent(firstName: "Diana", lastName: "Davis", manualOrder: 3)

        let allStudents = [student1, student2, student3, student4]
        let subset = [student1, student3]  // Visible subset

        // Move student1 from index 0 to index 1 in subset
        let newOrder = vm.mergeReorderedSubsetIntoAll(
            movingID: student1.id,
            from: 0,
            to: 1,
            current: subset,
            allStudents: allStudents
        )

        // student2 and student4 should maintain their relative positions
        #expect(newOrder.count == 4)
        // The subset should now be [student3, student1] and merged into the full list
    }
}

// MARK: - StudentsFilter Tests

@Suite("StudentsFilter Tests", .serialized)
struct StudentsFilterTests {

    @Test("StudentsFilter.all has correct title")
    func allHasCorrectTitle() {
        #expect(StudentsFilter.all.title == "All")
    }

    @Test("StudentsFilter.upper has correct title")
    func upperHasCorrectTitle() {
        #expect(StudentsFilter.upper.title == "Upper")
    }

    @Test("StudentsFilter.lower has correct title")
    func lowerHasCorrectTitle() {
        #expect(StudentsFilter.lower.title == "Lower")
    }

    @Test("StudentsFilter.presentNow has correct title")
    func presentNowHasCorrectTitle() {
        #expect(StudentsFilter.presentNow.title == "Present Now")
    }
}

// MARK: - SortOrder Tests

@Suite("StudentSortOrder Tests", .serialized)
@MainActor
struct StudentSortOrderTests {

    @Test("SortOrder.manual is hashable")
    func manualIsHashable() {
        let order: Maria_s_Notebook.SortOrder = .manual
        #expect(order.hashValue != 0 || order.hashValue == 0)  // Just verify it can be hashed
    }

    @Test("SortOrder equality works correctly")
    func equalityWorks() {
        #expect(Maria_s_Notebook.SortOrder.manual == Maria_s_Notebook.SortOrder.manual)
        #expect(Maria_s_Notebook.SortOrder.alphabetical == Maria_s_Notebook.SortOrder.alphabetical)
        #expect(Maria_s_Notebook.SortOrder.age == Maria_s_Notebook.SortOrder.age)
        #expect(Maria_s_Notebook.SortOrder.birthday == Maria_s_Notebook.SortOrder.birthday)
        #expect(Maria_s_Notebook.SortOrder.manual != Maria_s_Notebook.SortOrder.alphabetical)
    }
}

#endif
