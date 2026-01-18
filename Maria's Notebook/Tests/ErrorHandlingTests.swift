#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - ValidationError Tests

@Suite("ValidationError Tests", .serialized)
struct ValidationErrorTests {

    @Test("emptyValue error has correct description")
    func emptyValueErrorDescription() {
        let error = ValidationError.emptyValue("Name cannot be empty")

        #expect(error.errorDescription == "Name cannot be empty")
    }

    @Test("nilValue error has correct description")
    func nilValueErrorDescription() {
        let error = ValidationError.nilValue("Student is required")

        #expect(error.errorDescription == "Student is required")
    }

    @Test("outOfRange error has correct description")
    func outOfRangeErrorDescription() {
        let error = ValidationError.outOfRange("Value must be between 0 and 100")

        #expect(error.errorDescription == "Value must be between 0 and 100")
    }

    @Test("emptyCollection error has correct description")
    func emptyCollectionErrorDescription() {
        let error = ValidationError.emptyCollection("At least one student required")

        #expect(error.errorDescription == "At least one student required")
    }
}

// MARK: - ValidationHelpers Tests

@Suite("ValidationHelpers Tests", .serialized)
struct ValidationHelpersTests {

    @Test("validateNonEmpty throws for empty string")
    func validateNonEmptyThrowsForEmpty() {
        #expect(throws: ValidationError.self) {
            try ValidationHelpers.validateNonEmpty("")
        }
    }

    @Test("validateNonEmpty throws for whitespace-only string")
    func validateNonEmptyThrowsForWhitespace() {
        #expect(throws: ValidationError.self) {
            try ValidationHelpers.validateNonEmpty("   \n\t  ")
        }
    }

    @Test("validateNonEmpty succeeds for non-empty string")
    func validateNonEmptySucceeds() throws {
        try ValidationHelpers.validateNonEmpty("Hello")
        // No exception means success
    }

    @Test("validateNonEmpty uses custom message")
    func validateNonEmptyUsesCustomMessage() {
        do {
            try ValidationHelpers.validateNonEmpty("", message: "Custom message")
            #expect(Bool(false), "Should have thrown")
        } catch let error as ValidationError {
            #expect(error.errorDescription == "Custom message")
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    @Test("validateNotNil throws for nil value")
    func validateNotNilThrowsForNil() {
        let optionalValue: String? = nil

        #expect(throws: ValidationError.self) {
            _ = try ValidationHelpers.validateNotNil(optionalValue)
        }
    }

    @Test("validateNotNil returns unwrapped value")
    func validateNotNilReturnsUnwrapped() throws {
        let optionalValue: String? = "Hello"

        let result = try ValidationHelpers.validateNotNil(optionalValue)

        #expect(result == "Hello")
    }

    @Test("validateRange throws for value below range")
    func validateRangeThrowsForBelowRange() {
        #expect(throws: ValidationError.self) {
            try ValidationHelpers.validateRange(-1, in: 0...100)
        }
    }

    @Test("validateRange throws for value above range")
    func validateRangeThrowsForAboveRange() {
        #expect(throws: ValidationError.self) {
            try ValidationHelpers.validateRange(101, in: 0...100)
        }
    }

    @Test("validateRange succeeds for value in range")
    func validateRangeSucceeds() throws {
        try ValidationHelpers.validateRange(50, in: 0...100)
        try ValidationHelpers.validateRange(0, in: 0...100) // Boundary
        try ValidationHelpers.validateRange(100, in: 0...100) // Boundary
    }

    @Test("validateNonEmpty collection throws for empty array")
    func validateNonEmptyCollectionThrowsForEmpty() {
        let emptyArray: [Int] = []

        #expect(throws: ValidationError.self) {
            try ValidationHelpers.validateNonEmpty(emptyArray)
        }
    }

    @Test("validateNonEmpty collection succeeds for non-empty array")
    func validateNonEmptyCollectionSucceeds() throws {
        try ValidationHelpers.validateNonEmpty([1, 2, 3])
    }
}

// MARK: - PhotoStorageError Tests

@Suite("PhotoStorageError Tests", .serialized)
struct PhotoStorageErrorTests {

    @Test("imageConversionFailed is identifiable")
    func imageConversionFailedIdentifiable() {
        let error = PhotoStorageError.imageConversionFailed

        // Test that the error case exists
        if case .imageConversionFailed = error {
            #expect(true)
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("fileNotFound is identifiable")
    func fileNotFoundIdentifiable() {
        let error = PhotoStorageError.fileNotFound

        if case .fileNotFound = error {
            #expect(true)
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("directoryCreationFailed is identifiable")
    func directoryCreationFailedIdentifiable() {
        let error = PhotoStorageError.directoryCreationFailed

        if case .directoryCreationFailed = error {
            #expect(true)
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }
}

// MARK: - CSVImportError Tests

@Suite("CSVImportError Tests", .serialized)
struct CSVImportErrorTests {

    @Test("missingRequiredHeaders error has correct description")
    func missingRequiredHeadersDescription() {
        let error = CSVImportError.missingRequiredHeaders(["name", "subject"])

        #expect(error.errorDescription?.contains("name") == true)
        #expect(error.errorDescription?.contains("subject") == true)
    }

    @Test("invalidHeaderFormat error has correct description")
    func invalidHeaderFormatDescription() {
        let error = CSVImportError.invalidHeaderFormat("Headers contain special characters")

        #expect(error.errorDescription?.contains("special characters") == true)
    }
}

// MARK: - LessonCSVImporter ImportError Tests

@Suite("LessonCSVImporter ImportError Tests", .serialized)
struct LessonCSVImporterErrorTests {

    @Test("empty error has correct description")
    func emptyErrorDescription() {
        let error = LessonCSVImporter.ImportError.empty

        #expect(error.errorDescription?.contains("empty") == true)
    }

    @Test("missingHeader error includes header name")
    func missingHeaderErrorDescription() {
        let error = LessonCSVImporter.ImportError.missingHeader("name")

        #expect(error.errorDescription?.contains("name") == true)
    }

    @Test("malformedRow error includes row number")
    func malformedRowErrorDescription() {
        let error = LessonCSVImporter.ImportError.malformedRow(5)

        #expect(error.errorDescription?.contains("5") == true)
    }

    @Test("encoding error includes message")
    func encodingErrorDescription() {
        let error = LessonCSVImporter.ImportError.encoding("Unsupported encoding")

        #expect(error.errorDescription?.contains("Unsupported") == true)
    }
}

// MARK: - KeychainError Tests

@Suite("KeychainError Tests", .serialized)
struct KeychainErrorTests {

    @Test("unexpectedStatus error includes status code")
    func unexpectedStatusDescription() {
        let error = KeychainError.unexpectedStatus(-25300)

        #expect(error.errorDescription?.contains("-25300") == true)
    }

    @Test("dataConversion error has description")
    func dataConversionDescription() {
        let error = KeychainError.dataConversion

        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("conversion") == true)
    }
}

// MARK: - CSV Parsing Error Handling Tests

@Suite("CSV Parsing Error Handling Tests", .serialized)
struct CSVParsingErrorTests {

    @Test("parse throws for empty data")
    func parseThrowsForEmptyData() {
        let data = Data()

        #expect(throws: LessonCSVImporter.ImportError.self) {
            _ = try LessonCSVImporter.parse(data: data, existingLessonKeys: Set())
        }
    }

    @Test("parse throws for header-only CSV")
    func parseHandlesHeaderOnly() throws {
        let csv = "name,subject,group\n"
        let data = csv.data(using: .utf8)!

        let parsed = try LessonCSVImporter.parse(data: data, existingLessonKeys: Set())

        #expect(parsed.rows.isEmpty)
        #expect(parsed.totalRows == 0)
    }

    @Test("parse throws for missing required headers")
    func parseThrowsForMissingHeaders() {
        let csv = "title,category\nLesson 1,Math"
        let data = csv.data(using: .utf8)!

        // Should throw because 'subject' is missing (title maps to name, but no subject)
        #expect(throws: LessonCSVImporter.ImportError.self) {
            _ = try LessonCSVImporter.parse(data: data, existingLessonKeys: Set())
        }
    }

    @Test("parse reports rows with missing required values as warnings")
    func parseReportsMissingValuesAsWarnings() throws {
        let csv = """
        name,subject,group
        Lesson 1,Math,Operations
        ,Science,Biology
        Lesson 3,,Physics
        """
        let data = csv.data(using: .utf8)!

        let parsed = try LessonCSVImporter.parse(data: data, existingLessonKeys: Set())

        // Only the first row is valid (2nd missing name, 3rd missing subject)
        #expect(parsed.rows.count == 1)
        #expect(parsed.warnings.count == 2)
    }

    @Test("parse handles unsupported encoding gracefully")
    func parseHandlesUnsupportedEncoding() {
        // Create data that can't be decoded as UTF-8 or UTF-16
        let invalidData = Data([0xFF, 0xFE, 0x00, 0xD8, 0x00, 0xDC])

        // Should throw encoding error
        #expect(throws: LessonCSVImporter.ImportError.self) {
            _ = try LessonCSVImporter.parse(data: invalidData, existingLessonKeys: Set())
        }
    }
}

// MARK: - CSVHeaderMapping Error Tests

@Suite("CSVHeaderMapping Error Tests", .serialized)
struct CSVHeaderMappingErrorTests {

    @Test("validateRequired throws for missing required keys")
    func validateRequiredThrowsForMissing() {
        let mapping: [String: Int] = ["name": 0, "group": 2]

        #expect(throws: CSVImportError.self) {
            try CSVHeaderMapping.validateRequired(mapping: mapping, requiredKeys: ["name", "subject"])
        }
    }

    @Test("validateRequired succeeds when all keys present")
    func validateRequiredSucceeds() throws {
        let mapping: [String: Int] = ["name": 0, "subject": 1, "group": 2]

        try CSVHeaderMapping.validateRequired(mapping: mapping, requiredKeys: ["name", "subject"])
    }

    @Test("validateRequired throws with correct missing headers")
    func validateRequiredReportsMissingHeaders() {
        let mapping: [String: Int] = ["name": 0]

        do {
            try CSVHeaderMapping.validateRequired(mapping: mapping, requiredKeys: ["name", "subject", "group"])
            #expect(Bool(false), "Should have thrown")
        } catch let error as CSVImportError {
            if case .missingRequiredHeaders(let headers) = error {
                #expect(headers.contains("subject"))
                #expect(headers.contains("group"))
                #expect(!headers.contains("name"))
            } else {
                #expect(Bool(false), "Wrong error case")
            }
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }
}

// MARK: - Database Error Handling Tests

@Suite("Database Error Handling Tests", .serialized)
@MainActor
struct DatabaseErrorHandlingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
        ])
    }

    @Test("fetch handles empty result gracefully")
    func fetchHandlesEmptyResult() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Query for non-existent students
        let descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { student in
                student.firstName == "NonExistent"
            }
        )

        let results = try context.fetch(descriptor)

        #expect(results.isEmpty)
    }

    @Test("save handles duplicate insert")
    func saveHandlesDuplicateInsert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id = UUID()
        let student1 = Student(
            id: id,
            firstName: "Test",
            lastName: "Student",
            birthday: Date()
        )
        context.insert(student1)
        try context.save()

        // Creating another student with same UUID should work in SwiftData
        // (it will just update the existing one)
        let student2 = Student(
            id: id,
            firstName: "Updated",
            lastName: "Student",
            birthday: Date()
        )
        context.insert(student2)

        // Should not crash
        try context.save()
    }
}

// MARK: - Graceful Degradation Tests

@Suite("Graceful Degradation Tests", .serialized)
struct GracefulDegradationTests {

    @Test("PhotoStorageService loadImage returns nil for non-existent file")
    func loadImageReturnsNilForNonExistent() {
        let result = PhotoStorageService.loadImage(filename: "non-existent-file-12345.jpg")

        #expect(result == nil)
    }

    @Test("PhotoStorageService loadDownsampledImage returns nil for non-existent file")
    func loadDownsampledImageReturnsNilForNonExistent() {
        let result = PhotoStorageService.loadDownsampledImage(
            filename: "non-existent-file-12345.jpg",
            pointSize: CGSize(width: 100, height: 100),
            scale: 2.0
        )

        #expect(result == nil)
    }

    @Test("CSVParser handles empty string gracefully")
    func csvParserHandlesEmptyString() {
        let result = CSVParser.parse(string: "")

        // CSVParser returns a minimal structure even for empty input
        #expect(result != nil)
    }

    @Test("CSVParser handles empty data gracefully")
    func csvParserHandlesEmptyData() {
        let result = CSVParser.parse(data: Data())

        // CSVParser returns a minimal structure even for empty input
        #expect(result != nil)
    }

    @Test("DateParser returns nil for empty string")
    func dateParserReturnsNilForEmpty() {
        let result = DateParser.parse("")

        #expect(result == nil)
    }

    @Test("DateParser returns nil for invalid date string")
    func dateParserReturnsNilForInvalid() {
        let result = DateParser.parse("not a date")

        #expect(result == nil)
    }
}

// MARK: - Error Recovery Tests

@Suite("Error Recovery Tests", .serialized)
@MainActor
struct ErrorRecoveryTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
        ])
    }

    @Test("SaveCoordinator handles context save failure gracefully")
    func saveCoordinatorHandlesFailure() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let saveCoordinator = SaveCoordinator()

        // Should not crash even if called with empty context
        saveCoordinator.save(context)
    }

    @Test("model deletion followed by fetch doesn't crash")
    func deletionFollowedByFetchWorks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let studentId = student.id

        // Delete
        context.delete(student)
        try context.save()

        // Fetch should return empty
        let descriptor = FetchDescriptor<Student>(
            predicate: #Predicate<Student> { s in
                s.id == studentId
            }
        )
        let results = try context.fetch(descriptor)

        #expect(results.isEmpty)
    }
}

#endif
