import Foundation
import SwiftData

/// Property wrapper that automatically handles enum raw value storage for SwiftData models.
///
/// This wrapper eliminates the need for manual raw value properties and computed wrappers.
///
/// **Before:**
/// ```swift
/// private var statusRaw: String = WorkStatus.active.rawValue
/// var status: WorkStatus {
///     get { WorkStatus(rawValue: statusRaw) ?? .active }
///     set { statusRaw = newValue.rawValue }
/// }
/// ```
///
/// **After:**
/// ```swift
/// @RawCodable var status: WorkStatus = .active
/// ```
///
/// - Note: The default value is used as a fallback if the stored raw value is invalid.
/// - Important: This wrapper is designed for use with SwiftData models and CloudKit compatibility.
@propertyWrapper
struct RawCodable<T: RawRepresentable & Sendable>: Codable, Sendable where T.RawValue == String, T: Codable {
    private var storage: String
    private let defaultValue: T
    
    var wrappedValue: T {
        get { T(rawValue: storage) ?? defaultValue }
        set { storage = newValue.rawValue }
    }
    
    /// Initialize with a default value that serves as the fallback for invalid raw values
    init(wrappedValue: T) {
        self.defaultValue = wrappedValue
        self.storage = wrappedValue.rawValue
    }
    
    // MARK: - Codable Conformance
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.storage = try container.decode(String.self)
        // Default value must be provided during property declaration
        // We use a placeholder here that will be replaced by SwiftData
        self.defaultValue = T(rawValue: storage) ?? T(rawValue: "")!
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

// MARK: - SwiftData Helpers

extension RawCodable: Equatable where T: Equatable {
    static func == (lhs: RawCodable<T>, rhs: RawCodable<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension RawCodable: Hashable where T: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

// MARK: - Example Usage

/*
 Example usage in a SwiftData model:
 
 @Model
 final class WorkModel {
     // Instead of:
     // private var statusRaw: String = WorkStatus.active.rawValue
     // var status: WorkStatus {
     //     get { WorkStatus(rawValue: statusRaw) ?? .active }
     //     set { statusRaw = newValue.rawValue }
     // }
     
     // Simply write:
     @RawCodable var status: WorkStatus = .active
     
     // The wrapper automatically:
     // - Stores the raw value as a String (CloudKit compatible)
     // - Provides type-safe access to the enum
     // - Falls back to .active if raw value is invalid
     // - Supports Codable for backup/restore
 }
 
 enum WorkStatus: String, Codable, Sendable {
     case active
     case completed
     case archived
 }
 */
