import Foundation
import OSLog
import CoreData

// MARK: - JSON-Encoded String Array Storage

/// Provides encode/decode helpers for storing `[String]` arrays as JSON `Data`.
///
/// Used by SwiftData models that store UUID string arrays in `@Attribute(.externalStorage)` Data properties.
/// Standardizes error handling and eliminates duplicate encode/decode boilerplate across models.
///
/// **Usage in models:**
/// ```swift
/// @Attribute(.externalStorage) private var _studentIDsData: Data?
///
/// @Transient
/// var studentIDs: [String] {
///     get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
///     set { _studentIDsData = CloudKitStringArrayStorage.encode(newValue) }
/// }
/// ```
enum CloudKitStringArrayStorage {

    /// Shared coders. These accessors back `studentIDs` and friends, which are
    /// read inside whole-table filters (`assignments.filter { $0.studentIDs.contains(…) }`)
    /// hundreds of times per pass; building a fresh coder on every read was
    /// pure overhead. Neither is reconfigured after creation, so sharing is safe.
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    /// Decodes a JSON-encoded `Data` blob into a `[String]` array.
    /// Returns an empty array for `nil` data or decode failures.
    static func decode(from data: Data?) -> [String] {
        guard let data else { return [] }
        do {
            return try decoder.decode([String].self, from: data)
        } catch {
            let prefix = String(data.prefix(64).map { Character(UnicodeScalar($0)) })
            let count = data.count
            let desc = error.localizedDescription
            Logger.database.error(
                // swiftlint:disable:next line_length
                "CloudKitStringArrayStorage: Failed to decode [String] from \(count) bytes (prefix: \(prefix, privacy: .public)): \(desc, privacy: .public)"
            )
            return []
        }
    }

    /// Encodes a `[String]` array into JSON `Data` for storage.
    /// Returns `nil` on encode failure.
    static func encode(_ value: [String]) -> Data? {
        do {
            return try encoder.encode(value)
        } catch {
            Logger.database.warning(
                "CloudKitStringArrayStorage: Failed to encode \(value.count) strings: \(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Convenience: Encodes a `[UUID]` array as `[String]` JSON `Data`.
    static func encode(_ uuids: [UUID]) -> Data? {
        encode(uuids.map(\.uuidString))
    }
}
