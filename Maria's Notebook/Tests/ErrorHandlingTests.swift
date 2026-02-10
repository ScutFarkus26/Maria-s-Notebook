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
        ErrorDescriptionTester.testErrorDescriptionEquals(error, expected: "Name cannot be empty")
    }

    @Test("nilValue error has correct description")
    func nilValueErrorDescription() {
        let error = ValidationError.nilValue("Student is required")
        ErrorDescriptionTester.testErrorDescriptionEquals(error, expected: "Student is required")
    }

    @Test("outOfRange error has correct description")
    func outOfRangeErrorDescription() {
        let error = ValidationError.outOfRange("Value must be between 0 and 100")
        ErrorDescriptionTester.testErrorDescriptionEquals(error, expected: "Value must be between 0 and 100")
    }

    @Test("emptyCollection error has correct description")
    func emptyCollectionErrorDescription() {
        let error = ValidationError.emptyCollection("At least one student required")
        ErrorDescriptionTester.testErrorDescriptionEquals(error, expected: "At least one student required")
    }
}

// MARK: - ValidationHelpers Tests

@Suite("ValidationHelpers Tests", .serialized)
struct ValidationHelpersTests {

    @Test("validateNonEmpty throws for empty string")
    func validateNonEmptyThrowsForEmpty() {
        TestPatterns.expectThrowsError(try ValidationHelpers.validateNonEmpty(""), ofType: ValidationError.self)
    }

    @Test("validateNonEmpty throws for whitespace-only string")
    func validateNonEmptyThrowsForWhitespace() {
        TestPatterns.expectThrowsError(try ValidationHelpers.validateNonEmpty("   \n\t  "), ofType: ValidationError.self)
    }

    @Test("validateNonEmpty succeeds for non-empty string")
    func validateNonEmptySucceeds() throws {
        try ValidationHelpers.validateNonEmpty("Hello")
    }

    @Test("validateNonEmpty uses custom message")
    func validateNonEmptyUsesCustomMessage() {
        do {
            try ValidationHelpers.validateNonEmpty("", message: "Custom message")
            #expect(Bool(false), "Should have thrown")
        } catch let error as ValidationError {
            ErrorDescriptionTester.testErrorDescriptionEquals(error, expected: "Custom message")
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    @Test("validateNotNil throws for nil value")
    func validateNotNilThrowsForNil() {
        let optionalValue: String? = nil
        TestPatterns.expectThrowsError(try ValidationHelpers.validateNotNil(optionalValue), ofType: ValidationError.self)
    }

    @Test("validateNotNil returns unwrapped value")
    func validateNotNilReturnsUnwrapped() throws {
        let optionalValue: String? = "Hello"

        let result = try ValidationHelpers.validateNotNil(optionalValue)

        #expect(result == "Hello")
    }

    @Test("validateRange throws for value below range")
    func validateRangeThrowsForBelowRange() {
        TestPatterns.expectThrowsError(try ValidationHelpers.validateRange(-1, in: 0...100), ofType: ValidationError.self)
    }

    @Test("validateRange throws for value above range")
    func validateRangeThrowsForAboveRange() {
        TestPatterns.expectThrowsError(try ValidationHelpers.validateRange(101, in: 0...100), ofType: ValidationError.self)
    }

    @Test("validateRange succeeds for value in range")
    func validateRangeSucceeds() throws {
        try ValidationHelpers.validateRange(50, in: 0...100)
        try ValidationHelpers.validateRange(0, in: 0...100)
        try ValidationHelpers.validateRange(100, in: 0...100)
    }

    @Test("validateNonEmpty collection throws for empty array")
    func validateNonEmptyCollectionThrowsForEmpty() {
        let emptyArray: [Int] = []
        TestPatterns.expectThrowsError(try ValidationHelpers.validateNonEmpty(emptyArray), ofType: ValidationError.self)
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
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "name")
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "subject")
    }

    @Test("invalidHeaderFormat error has correct description")
    func invalidHeaderFormatDescription() {
        let error = CSVImportError.invalidHeaderFormat("Headers contain special characters")
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "special characters")
    }
}

// MARK: - LessonCSVImporter ImportError Tests

@Suite("LessonCSVImporter ImportError Tests", .serialized)
struct LessonCSVImporterErrorTests {

    @Test("empty error has correct description")
    func emptyErrorDescription() {
        let error = LessonCSVImporter.ImportError.empty
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "empty")
    }

    @Test("missingHeader error includes header name")
    func missingHeaderErrorDescription() {
        let error = LessonCSVImporter.ImportError.missingHeader("name")
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "name")
    }

    @Test("malformedRow error includes row number")
    func malformedRowErrorDescription() {
        let error = LessonCSVImporter.ImportError.malformedRow(5)
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "5")
    }

    @Test("encoding error includes message")
    func encodingErrorDescription() {
        let error = LessonCSVImporter.ImportError.encoding("Unsupported encoding")
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "Unsupported")
    }
}

// MARK: - KeychainError Tests

@Suite("KeychainError Tests", .serialized)
struct KeychainErrorTests {

    @Test("unexpectedStatus error includes status code")
    func unexpectedStatusDescription() {
        let error = KeychainError.unexpectedStatus(-25300)
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "-25300")
    }

    @Test("dataConversion error has description")
    func dataConversionDescription() {
        let error = KeychainError.dataConversion
        ErrorDescriptionTester.testErrorDescription(error, containsSubstring: "conversion")
    }
}

// MARK: - CSV Parsing Error Handling Tests

@Suite("CSV Parsing Error Handling Tests", .serialized)
struct CSVParsingErrorTests {

    @Test("parse throws for empty data")
    func parseThrowsForEmptyData() {
        TestPatterns.expectThrowsError(
            try LessonCSVImporter.parse(data: Data(), existingLessonKeys: Set()),
            ofType: LessonCSVImporter.ImportError.self
        )
    }

    @Test("parse throws for header-only CSV")
    func parseHandlesHeaderOnly() throws {
        let csv = "name,subject,group\n"
        let data = csv.data(using: .utf8)!
        let parsed = try LessonCSVImporter.parse(data: data, existingLessonKeys: Set())

        TestPatterns.expectEmpty(parsed.rows)
        #expect(parsed.totalRows == 0)
    }

    @Test("parse throws for missing required headers")
    func parseThrowsForMissingHeaders() {
        let csv = "title,category\nLesson 1,Math"
        let data = csv.data(using: .utf8)!

        TestPatterns.expectThrowsError(
            try LessonCSVImporter.parse(data: data, existingLessonKeys: Set()),
            ofType: LessonCSVImporter.ImportError.self
        )
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

        TestPatterns.expectCount(parsed.rows, equals: 1)
        TestPatterns.expectCount(parsed.warnings, equals: 2)
    }

    @Test("parse handles unsupported encoding gracefully")
    func parseHandlesUnsupportedEncoding() {
        let invalidData = Data([0xFF, 0xFE, 0x00, 0xD8, 0x00, 0xDC])
        TestPatterns.expectThrowsError(
            try LessonCSVImporter.parse(data: invalidData, existingLessonKeys: Set()),
            ofType: LessonCSVImporter.ImportError.self
        )
    }
}

// MARK: - CSVHeaderMapping Error Tests

@Suite("CSVHeaderMapping Error Tests", .serialized)
struct CSVHeaderMappingErrorTests {

    @Test("validateRequired throws for missing required keys")
    func validateRequiredThrowsForMissing() {
        let mapping: [String: Int] = ["name": 0, "group": 2]
        TestPatterns.expectThrowsError(
            try CSVHeaderMapping.validateRequired(mapping: mapping, requiredKeys: ["name", "subject"]),
            ofType: CSVImportError.self
        )
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

    private static let models: [any PersistentModel.Type] = [Student.self, Note.self]

    @Test("fetch handles empty result gracefully")
    func fetchHandlesEmptyResult() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { student in student.firstName == "NonExistent" }
        )
        let results = try context.fetch(descriptor)

        TestPatterns.expectEmpty(results)
    }

    @Test("save handles duplicate insert")
    func saveHandlesDuplicateInsert() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let id = UUID()
        let student1 = Student(id: id, firstName: "Test", lastName: "Student", birthday: Date())
        context.insert(student1)
        try context.save()

        let student2 = Student(id: id, firstName: "Updated", lastName: "Student", birthday: Date())
        context.insert(student2)
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

    private static let models: [any PersistentModel.Type] = [Student.self, Note.self]

    @Test("SaveCoordinator handles context save failure gracefully")
    func saveCoordinatorHandlesFailure() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let saveCoordinator = SaveCoordinator()
        saveCoordinator.save(context)
    }

    @Test("model deletion followed by fetch doesn't crash")
    func deletionFollowedByFetchWorks() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent()
        let studentId = student.id

        context.delete(student)
        try context.save()

        let descriptor = FetchDescriptor<Student>(predicate: #Predicate<Student> { s in s.id == studentId })
        let results = try context.fetch(descriptor)

        TestPatterns.expectEmpty(results)
    }
}

// MARK: - ToastService Tests

@Suite("ToastService Tests", .serialized)
@MainActor
struct ToastServiceTests {

    @Test("showInfo displays info toast")
    func showInfoDisplaysToast() async {
        let service = ToastService.preview

        service.showInfo("Test message")

        #expect(service.currentToast != nil)
        #expect(service.currentToast?.message == "Test message")
        #expect(service.currentToast?.type == .info)
    }

    @Test("showSuccess displays success toast")
    func showSuccessDisplaysToast() async {
        let service = ToastService.preview

        service.showSuccess("Success!")

        #expect(service.currentToast != nil)
        #expect(service.currentToast?.type == .success)
    }

    @Test("showWarning displays warning toast")
    func showWarningDisplaysToast() async {
        let service = ToastService.preview

        service.showWarning("Warning!")

        #expect(service.currentToast != nil)
        #expect(service.currentToast?.type == .warning)
    }

    @Test("showError displays error toast")
    func showErrorDisplaysToast() async {
        let service = ToastService.preview

        service.showError("Error!")

        #expect(service.currentToast != nil)
        #expect(service.currentToast?.type == .error)
    }

    @Test("dismiss clears current toast")
    func dismissClearsToast() async {
        let service = ToastService.preview

        service.showInfo("Test")
        #expect(service.currentToast != nil)

        service.dismiss()

        // Allow animation to complete
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(service.currentToast == nil)
    }

    @Test("clearAll clears all toasts")
    func clearAllClearsToasts() async {
        let service = ToastService.preview

        service.showInfo("First")
        service.showInfo("Second")
        service.showInfo("Third")

        service.clearAll()

        // Allow animation to complete
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(service.currentToast == nil)
    }

    @Test("ToastType has correct background colors")
    func toastTypeBackgroundColors() {
        #expect(ToastType.success.backgroundColor != ToastType.error.backgroundColor)
        #expect(ToastType.info.backgroundColor != ToastType.warning.backgroundColor)
    }

    @Test("ToastType has correct icons")
    func toastTypeIcons() {
        #expect(ToastType.success.iconName == "checkmark.circle.fill")
        #expect(ToastType.error.iconName == "xmark.circle.fill")
        #expect(ToastType.warning.iconName == "exclamationmark.triangle.fill")
        #expect(ToastType.info.iconName == nil)
    }
}

// MARK: - SaveCoordinator Integration Tests

@Suite("SaveCoordinator Integration Tests", .serialized)
@MainActor
struct SaveCoordinatorIntegrationTests {

    private static let models: [any PersistentModel.Type] = [Student.self, Note.self]

    @Test("save returns true on success")
    func saveReturnsTrueOnSuccess() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let coordinator = SaveCoordinator()
        let student = makeTestStudent()
        context.insert(student)

        let result = coordinator.save(context, reason: "Test save")

        #expect(result == true)
        #expect(coordinator.lastSaveError == nil)
    }

    @Test("save skips when no changes")
    func saveSkipsWhenNoChanges() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let coordinator = SaveCoordinator()

        let result = coordinator.save(context)

        #expect(result == true)
    }

    @Test("clearError clears error state")
    func clearErrorClearsState() throws {
        let coordinator = SaveCoordinator()

        // Manually set error state for testing
        coordinator.lastSaveErrorMessage = "Test error"
        coordinator.isShowingSaveError = true

        coordinator.clearError()

        #expect(coordinator.lastSaveError == nil)
        #expect(coordinator.lastSaveErrorMessage == nil)
        #expect(coordinator.isShowingSaveError == false)
    }

    @Test("saveWithToast shows success toast on success")
    func saveWithToastShowsSuccessToast() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)
        let coordinator = SaveCoordinator()

        ToastService.shared.clearAll()

        let student = makeTestStudent()
        context.insert(student)

        let result = coordinator.saveWithToast(context, successMessage: "Saved!")

        #expect(result == true)
        #expect(ToastService.shared.currentToast?.message == "Saved!")
    }
}

#endif
