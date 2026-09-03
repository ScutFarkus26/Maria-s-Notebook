import Foundation
import Testing
@testable import Maria_s_Notebook

struct StudentFormatterTests {

    @Test("Shortened name is the first name plus the last initial with no period")
    func normalName() {
        #expect(StudentFormatter.displayName(firstName: "Maya", lastName: "Sanchez") == "Maya S")
    }

    @Test("A two-word first name keeps both words")
    func twoWordFirstName() {
        #expect(StudentFormatter.displayName(firstName: "Mary Kate", lastName: "Ross") == "Mary Kate R")
    }

    @Test("A missing last name shows just the first name")
    func missingLastName() {
        #expect(StudentFormatter.displayName(firstName: "Maya", lastName: "") == "Maya")
    }

    @Test("Whitespace-padded fields are trimmed before formatting")
    func paddedFields() {
        #expect(StudentFormatter.displayName(firstName: "  Maya ", lastName: " Sanchez ") == "Maya S")
        #expect(StudentFormatter.displayName(firstName: "Maya", lastName: "   ") == "Maya")
    }

    @Test("The initial is uppercased even for a lowercase last name")
    func lowercaseLastName() {
        #expect(StudentFormatter.displayName(firstName: "Maya", lastName: "de Souza") == "Maya D")
    }

    @Test("The CDStudent overloads read the stored first and last name fields")
    @MainActor
    func entityOverloads() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let student = CoreDataTestHelpers.seedStudent(
            in: stack.viewContext, firstName: " Mary Kate ", lastName: "Ross"
        )
        #expect(StudentFormatter.displayName(for: student) == "Mary Kate R")
        #expect(StudentFormatter.firstName(for: student) == "Mary Kate")
    }
}
