import SwiftData
import Foundation

#if DEBUG
/// DEBUG-only helper to detect WorkContract read paths in UI code (excluding MigrationRunner).
/// This helps ensure UI is using WorkModel instead of WorkContract.
enum WorkContractReadPathDetector {
    /// Checks if any WorkContract records are being fetched in UI code.
    /// Call this from UI views to detect if WorkContract is still being read.
    /// - Parameter context: The ModelContext to check
    /// - Parameter caller: The name of the calling function/view (for logging)
    static func detectReadPath(context: ModelContext, caller: String) {
        let descriptor = FetchDescriptor<WorkContract>()
        if let contracts = try? context.fetch(descriptor), contracts.count > 0 {
            print("⚠️ WARNING: WorkContract read-path detected in \(caller) - found \(contracts.count) contracts. UI should use WorkModel instead.")
        }
    }
    
    /// Checks if a specific WorkContract is being accessed by ID.
    /// - Parameter context: The ModelContext to check
    /// - Parameter contractID: The WorkContract ID being accessed
    /// - Parameter caller: The name of the calling function/view (for logging)
    static func detectReadPath(context: ModelContext, contractID: UUID, caller: String) {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == contractID })
        if let contracts = try? context.fetch(descriptor), contracts.count > 0 {
            print("⚠️ WARNING: WorkContract read-path detected in \(caller) for contractID \(contractID.uuidString). UI should use WorkModel instead.")
        }
    }
}
#endif
