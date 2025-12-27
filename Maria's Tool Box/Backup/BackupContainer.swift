// Create a minimal BackupContainer type so BackupService compiles.
// This can be expanded later with full Codable arrays for each model.
import Foundation

struct BackupContainer: Codable, Sendable {
    var version: Int
    var exportedAt: Date
    // Add full entity payloads here when ready
    // For now we keep it minimal to fix the build.
    init(version: Int, exportedAt: Date) {
        self.version = version
        self.exportedAt = exportedAt
    }
}
