import Foundation
import SwiftData

#if DEBUG
/// DEBUG-only guardrail to prevent new WorkContract inserts.
/// Wrap ModelContext.insert calls with this function to catch WorkContract insertions.
extension ModelContext {
    /// Safe insert that guards against WorkContract inserts in DEBUG builds.
    /// Use this instead of direct context.insert() to catch WorkContract creation attempts.
    func safeInsert<T: PersistentModel>(_ model: T) {
        if model is WorkContract {
            let message = "⚠️ Attempted to insert WorkContract. WorkContract is read-only for legacy data. Use WorkModel instead."
            print(message)
            // In DEBUG builds, break into debugger to catch the call site
            assertionFailure(message)
        }
        insert(model)
    }
}
#endif

