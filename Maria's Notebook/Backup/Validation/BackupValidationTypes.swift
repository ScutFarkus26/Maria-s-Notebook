import Foundation

// MARK: - Backup Validation Types

extension BackupValidationService {

    public struct ValidationResult {
        public var isValid: Bool
        public var errors: [ValidationError]
        public var warnings: [ValidationWarning]
        public var recommendations: [String]
        public var entityTypeDetails: [String: EntityTypeValidation]

        public var canProceed: Bool {
            // Can proceed if valid or only has warnings
            return isValid || errors.isEmpty
        }
    }

    public struct EntityTypeValidation {
        public let entityType: String
        public let willInsert: Int
        public let willUpdate: Int
        public let willSkip: Int
        public let willDelete: Int
        public let issues: [String]
    }

    public struct ValidationError: Identifiable {
        public let id = UUID()
        public let entityType: String
        public let entityID: UUID?
        public let field: String?
        public let message: String
        public let severity: Severity

        public enum Severity {
            case critical  // Will prevent restore
            case error     // Should prevent restore
            case warning   // Can proceed with caution
        }
    }

    public struct ValidationWarning: Identifiable {
        public let id = UUID()
        public let message: String
        public let recommendation: String?
    }
}
