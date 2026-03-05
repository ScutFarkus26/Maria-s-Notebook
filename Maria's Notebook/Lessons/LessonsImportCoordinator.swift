import Foundation
import SwiftData

@MainActor
struct LessonsImportCoordinator {
    static func startImport(
        from url: URL,
        lessons: [Lesson],
        onParsed: @MainActor @Sendable @escaping (LessonCSVImporter.Parsed) -> Void,
        onError: @MainActor @Sendable @escaping (Error) -> Void,
        onFinally: @MainActor @Sendable @escaping () -> Void
    ) -> Task<Void, Never> {
        return Task(priority: .userInitiated) { @MainActor in
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
                
                let parsed = try await MainActor.run {
                    try LessonCSVImporter.parse(data: data, existingLessonKeys: existingKeys)
                }
                
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
