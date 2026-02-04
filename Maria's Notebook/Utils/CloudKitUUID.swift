import Foundation
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

// MARK: - Example Usage

/*
 Example usage in a SwiftData model:
 
 @Model
 final class WorkModel {
     // Before:
     // var studentID: String = ""
     // var lessonID: String = ""
     // var presentationID: String? = nil
     
     // After - Type-safe with CloudKit compatibility:
     @CloudKitUUID var studentID: UUID = UUID()
     @CloudKitUUID var lessonID: UUID = UUID()
     var presentationID: String? = nil  // Keep optional IDs as regular properties
     
     // SwiftData stores as String, code uses UUID
     
     // Access the UUID directly:
     func doWork() {
         let id = studentID  // UUID type
         print(id.uuidString)
     }
     
     // Access the String via projected value if needed:
     func cloudKitSync() {
         let stringID = $studentID  // String type for CloudKit
     }
 }
 
 // For arrays of UUIDs:
 @Model
 final class StudentLesson {
     // Store as Data but access as [UUID]
     @Attribute(.externalStorage) private var _studentIDsData: Data
     
     var studentIDs: [UUID] {
         get {
             (try? JSONDecoder().decode([String].self, from: _studentIDsData))
                 .map { Array(cloudKitStrings: $0) } ?? []
         }
         set {
             _studentIDsData = (try? JSONEncoder().encode(newValue.cloudKitStrings)) ?? Data()
         }
     }
 }
 */
