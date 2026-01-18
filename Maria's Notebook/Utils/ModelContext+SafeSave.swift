import Foundation
import SwiftData

/// Extensions for safe ModelContext save operations
/// Improves error visibility and debugging capabilities
extension ModelContext {
    /// Saves context and logs errors instead of silently failing
    /// Use this for non-critical saves where failure can be tolerated
    func safeSave() {
        do {
            try save()
        } catch {
            #if DEBUG
            print("⚠️ ModelContext save failed: \(error.localizedDescription)")
            #endif
            // Optionally: send to crash reporting service
        }
    }
    
    /// Saves context and throws errors (for critical operations)
    /// Use this when save failures must be handled by the caller
    func saveOrThrow() throws {
        try save()
    }
}

