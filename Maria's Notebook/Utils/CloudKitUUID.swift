import Foundation
import OSLog
import SwiftData

/// Property wrapper that provides type-safe UUID access while storing as String for CloudKit compatibility.
///
/// This wrapper eliminates the need for manual UUID ↔ String conversions throughout the codebase.
///
/// **Problem it solves:**
/// CloudKit requires UUID foreign keys to be stored as String, but working with strings is error-prone:
/// - No type safety (any string accepted)
/// - Manual UUID(uuidString:) conversions everywhere
/// - Empty string "" defaults lead to lost references
///
/// **Before:**
/// ```swift
/// var studentID: String = ""  // CloudKit compatible but not type-safe
///
/// // Later in code:
/// if let uuid = UUID(uuidString: work.studentID) {
///     // Use uuid
/// }
/// ```
///
/// **After:**
/// ```swift
/// @CloudKitUUID var studentID: UUID = UUID()  // Type-safe access, String storage
///
/// // Later in code:
/// let uuid = work.studentID  // Already a UUID!
/// ```
///
/// - Note: Invalid strings automatically generate a new UUID (safe default)
/// - Important: SwiftData persists the underlying String for CloudKit compatibility
@propertyWrapper
struct CloudKitUUID: Codable, Hashable, Sendable {
    private var storage: String
    
    var wrappedValue: UUID {
        get { UUID(uuidString: storage) ?? UUID() }
        set { storage = newValue.uuidString }
    }
    
    /// Projected value provides access to the underlying String for CloudKit operations
    var projectedValue: String {
        get { storage }
        set { storage = newValue }
    }
    
    /// Initialize with a UUID value
    init(wrappedValue: UUID) {
        self.storage = wrappedValue.uuidString
    }
    
    /// Initialize with a String value (for CloudKit deserialization)
    init(stringValue: String) {
        self.storage = stringValue
    }
    
    // MARK: - Codable Conformance
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.storage = try container.decode(String.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
    
    // MARK: - Hashable Conformance
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(storage)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage == rhs.storage
    }
}

// MARK: - Optional Support

extension CloudKitUUID {
    /// Initialize with an optional UUID (nil becomes a new UUID)
    init(optionalValue: UUID?) {
        self.storage = (optionalValue ?? UUID()).uuidString
    }
}

// MARK: - Array Support

extension Array where Element == UUID {
    /// Convert UUID array to String array for CloudKit storage
    var cloudKitStrings: [String] {
        map(\.uuidString)
    }
    
    /// Initialize from String array (CloudKit deserialization)
    init(cloudKitStrings: [String]) {
        self = cloudKitStrings.compactMap { UUID(uuidString: $0) }
    }
}

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

    /// Decodes a JSON-encoded `Data` blob into a `[String]` array.
    /// Returns an empty array for `nil` data or decode failures.
    static func decode(from data: Data?) -> [String] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            let desc = error.localizedDescription
            Logger.database.warning(
                "CloudKitStringArrayStorage: Failed to decode [String] from \(data.count) bytes: \(desc)"
            )
            return []
        }
    }

    /// Encodes a `[String]` array into JSON `Data` for storage.
    /// Returns `nil` on encode failure.
    static func encode(_ value: [String]) -> Data? {
        do {
            return try JSONEncoder().encode(value)
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
