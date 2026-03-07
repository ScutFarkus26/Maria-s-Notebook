import Foundation
import SwiftData

@MainActor
struct StudentsImportCoordinator {
    static func startHeaderScan(
        from url: URL,
        onParsed: @MainActor @Sendable @escaping (
            _ headers: [String], _ suggestedMapping: StudentCSVImporter.Mapping
        ) -> Void,
        onError: @MainActor @Sendable @escaping (Error) -> Void,
        onFinally: @MainActor @Sendable @escaping () -> Void
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) { @MainActor in
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw StudentCSVImporter.ImportError.encoding("Could not access security scoped resource.")
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard let csv = CSVParser.parse(data: data) else {
                    throw StudentCSVImporter.ImportError.encoding("Unsupported text encoding; please use UTF-8.")
                }

                let mapping = StudentCSVImporter.detectMapping(headers: csv.headers)

                onParsed(csv.headers, mapping)
            } catch is CancellationError {
                // silently ignore cancellation
            } catch {
                onError(error)
            }
            onFinally()
        }
    }

    // swiftlint:disable:next function_parameter_count
    static func startMappedParse(
        from url: URL,
        mapping: StudentCSVImporter.Mapping,
        students: [Student],
        onParsed: @MainActor @Sendable @escaping (StudentCSVImporter.Parsed) -> Void,
        onError: @MainActor @Sendable @escaping (Error) -> Void,
        onFinally: @MainActor @Sendable @escaping () -> Void
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) { @MainActor in
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw StudentCSVImporter.ImportError.encoding("Could not access security scoped resource.")
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url, options: [.mappedIfSafe])

                let full = Set(students.map { StudentCSVImporter.duplicateKey(for: $0) })
                let name = Set(students.map { ("\($0.firstName) \($0.lastName)").normalizedNameKey() })

                let parsed = try StudentCSVImporter.parse(
                    data: data,
                    mapping: mapping,
                    existingFullKeys: full,
                    existingNameKeys: name
                )

                onParsed(parsed)
            } catch is CancellationError {
                // silently ignore cancellation
            } catch {
                onError(error)
            }
            onFinally()
        }
    }
}
