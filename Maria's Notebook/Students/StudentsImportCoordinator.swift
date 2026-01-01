import Foundation
import SwiftData

struct StudentsImportCoordinator {
    static func startHeaderScan(
        from url: URL,
        onParsed: @escaping (_ headers: [String], _ suggestedMapping: StudentCSVImporter.Mapping) -> Void,
        onError: @escaping (Error) -> Void,
        onFinally: @escaping () -> Void
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) {
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
                
                await MainActor.run {
                    onParsed(csv.headers, mapping)
                }
            } catch is CancellationError {
                // silently ignore cancellation
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
            await MainActor.run {
                onFinally()
            }
        }
    }
    
    static func startMappedParse(
        from url: URL,
        mapping: StudentCSVImporter.Mapping,
        students: [Student],
        onParsed: @escaping (StudentCSVImporter.Parsed) -> Void,
        onError: @escaping (Error) -> Void,
        onFinally: @escaping () -> Void
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw StudentCSVImporter.ImportError.encoding("Could not access security scoped resource.")
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                
                let keys = await MainActor.run { () -> (full: Set<String>, name: Set<String>) in
                    let full = Set(students.map { StudentCSVImporter.duplicateKey(for: $0) })
                    let name = Set(students.map { ("\($0.firstName) \($0.lastName)").normalizedNameKey() })
                    return (full, name)
                }
                
                let parsed = try StudentCSVImporter.parse(
                    data: data,
                    mapping: mapping,
                    existingFullKeys: keys.full,
                    existingNameKeys: keys.name
                )
                
                await MainActor.run {
                    onParsed(parsed)
                }
            } catch is CancellationError {
                // silently ignore cancellation
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
            await MainActor.run {
                onFinally()
            }
        }
    }
}
