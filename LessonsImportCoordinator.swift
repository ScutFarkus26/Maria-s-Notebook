import Foundation
import SwiftData

struct LessonsImportCoordinator {
    static func startImport(
        from url: URL,
        lessons: [Lesson],
        onParsed: @escaping (LessonCSVImporter.Parsed) -> Void,
        onError: @escaping (Error) -> Void,
        onFinally: @escaping () -> Void
    ) -> Task<Void, Never> {
        return Task(priority: .userInitiated) {
            guard url.startAccessingSecurityScopedResource() else {
                await MainActor.run {
                    onError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: nil))
                    onFinally()
                }
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in
                    onFinally()
                }
            }
            
            do {
                let data = try Data(contentsOf: url)
                
                let existingKeys = await MainActor.run {
                    Set(lessons.map { LessonCSVImporter.duplicateKey(for: $0) })
                }
                
                try Task.checkCancellation()
                
                let parsed = try await Task.detached {
                    try Task.checkCancellation()
                    return try LessonCSVImporter.parse(data: data, existingLessonKeys: existingKeys)
                }.value
                
                try Task.checkCancellation()
                
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
        }
    }
}
