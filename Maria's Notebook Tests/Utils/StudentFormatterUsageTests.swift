import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Pins the roster cases that used to be rendered by eight local copies of the
/// short-name rule — five of which printed a trailing period, and some of which
/// fell back to a bare first name that could not tell two children apart.
/// Everything on screen now goes through `StudentFormatter`.
@MainActor
struct StudentFormatterUsageTests {

    /// Held for the lifetime of the test instance: the seeded students are
    /// managed objects, and they stop answering once their stack goes away.
    private let stack: CoreDataStack
    private let students: [String: CDStudent]

    init() throws {
        stack = try CoreDataTestHelpers.makeInMemoryStack()
        let roster = [
            ("Etty", "Dechter"), ("Etty", "Krinsky"),
            ("Sarah", "Markewitz"), ("Sarah", "Zakon"),
            ("Maya", "Sanchez"), ("Tiferet", "Pardo"),
            ("Etty", "")
        ]
        var byKey: [String: CDStudent] = [:]
        for (first, last) in roster {
            let student = CoreDataTestHelpers.seedStudent(
                in: stack.viewContext, firstName: first, lastName: last
            )
            student.id = UUID()
            byKey["\(first) \(last)".trimmed()] = student
        }
        students = byKey
    }

    private func student(_ key: String) throws -> CDStudent {
        try #require(students[key], "\(key) was not seeded")
    }

    @Test("Two children sharing a first name render distinctly")
    func collidingFirstNames() throws {
        #expect(StudentFormatter.displayName(for: try student("Etty Dechter")) == "Etty D")
        #expect(StudentFormatter.displayName(for: try student("Etty Krinsky")) == "Etty K")
        #expect(StudentFormatter.displayName(for: try student("Sarah Markewitz")) == "Sarah M")
        #expect(StudentFormatter.displayName(for: try student("Sarah Zakon")) == "Sarah Z")
    }

    @Test("A child with a unique first name keeps her last initial too")
    func uniqueFirstNameKeepsInitial() throws {
        #expect(StudentFormatter.displayName(for: try student("Maya Sanchez")) == "Maya S")
        #expect(StudentFormatter.displayName(for: try student("Tiferet Pardo")) == "Tiferet P")
    }

    @Test("No rendered short name ends in a period or a stray space")
    func noTrailingPeriod() {
        for student in students.values {
            let name = StudentFormatter.displayName(for: student)
            #expect(!name.isEmpty)
            #expect(!name.hasSuffix("."), "\(name) should not end in a period")
            #expect(!name.hasSuffix(" "), "\(name) should not end in a space")
        }
    }

    @Test("A colliding child with no last name still renders cleanly")
    func emptyLastName() throws {
        #expect(StudentFormatter.displayName(for: try student("Etty")) == "Etty")
    }

    @Test("Today's cached lookup renders the canonical short name for an ID")
    func todayCacheManagerUsesTheFormatter() throws {
        let etty = try student("Etty Dechter")
        let otherEtty = try student("Etty Krinsky")
        let ids = Set([etty, otherEtty].compactMap(\.id))

        let cache = TodayCacheManager()
        cache.loadStudentsIfNeeded(ids: ids, context: stack.viewContext)

        #expect(cache.displayName(for: try #require(etty.id)) == "Etty D")
        #expect(cache.displayName(for: try #require(otherEtty.id)) == "Etty K")
        #expect(cache.displayName(for: UUID()) == "Student")
    }
}
