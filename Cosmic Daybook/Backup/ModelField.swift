// ModelField.swift
// The pieces of a `ModelRowSpec`: one value, one key and how it is read and
// written, and how a row is re-linked to its parent (see ModelRow.swift).

import CoreData
import Foundation

/// One value in a backup row, typed as the DTO field it replaces was, so it
/// encodes and decodes to the same JSON.
nonisolated public enum ModelValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case uuid(UUID)
    case strings([String])
    case data(Data)
    /// Ids written as a list (a student's next lessons), for a computed field.
    case uuids([UUID])
    /// Rows of numbers (a highlight's rectangles), for a computed field.
    case doubleArrays([[Double]])

    /// The value as Core Data stores it.
    var storedValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): NSNumber(value: value)
        case .double(let value): NSNumber(value: value)
        case .bool(let value): NSNumber(value: value)
        case .date(let value): value
        case .uuid(let value): value
        case .strings(let value): value as NSArray
        case .data(let value): value
        case .uuids(let value): value.map(\.uuidString) as NSArray
        case .doubleArrays(let value): value as NSArray
        }
    }
}

/// One key of a backup row.
nonisolated public struct ModelField: Sendable {
    public enum Kind: Sendable {
        case string, int, double, bool, date, uuid, strings, data, uuids, doubleArrays
    }

    /// Where the value comes from and goes to.
    public enum Source: Sendable {
        /// The named model attribute (the key itself, unless the spec renames it).
        case attribute(String)
        /// The `id` of the parent reached through this to-one relationship.
        /// Written on export; the restore re-links through `ParentLink`.
        case parentID(relationship: String)
        /// Read and written by code: a value the old hand-written code reshaped
        /// (an enum read through its typed accessor, a list kept as a blob).
        case computed(ModelFieldCode)
    }

    let key: String
    let kind: Kind
    let source: Source
    /// Every row has it: the attribute is non-optional, or the export fills it.
    let required: Bool
    /// The export writes a made-up value when the attribute is nil: a new id,
    /// the current time, or an empty list.
    let filled: Bool
    /// Added after the type's first format: a row without it leaves the
    /// record's value alone instead of clearing it.
    let keptWhenMissing: Bool
    /// A string attribute holding an id, carried as a UUID: written only when
    /// it parses, restored as its `uuidString`.
    var storedAsString = false
    /// A record with no value for it isn't backed up (the old `guard let`).
    var dropsRecordWhenMissing = false
    /// What a row without it reads as (the old lenient decoders' "" and 0).
    var defaultWhenMissing: ModelValue?
    /// A row without it reads as the moment it is read: the old lenient
    /// decoders' `?? Date()`, which a fixed `defaultWhenMissing` can't say.
    var nowWhenMissing = false
    /// The only strings a row may hold under it; any other fails the decode,
    /// as the old enum-typed field did.
    var allowedStrings: Set<String>?

    /// A field read and written by code. `write` gets the row's value for
    /// `key` (nil when the row has none, unless `kept`, when it isn't called)
    /// and the whole row, for a value that depends on another key.
    static func computed<Object: NSManagedObject>(
        _ key: String,
        _ kind: Kind,
        of type: Object.Type,
        required: Bool = false,
        kept: Bool = false,
        dropsRecordWhenMissing: Bool = false,
        defaultWhenMissing: ModelValue? = nil,
        allowedStrings: Set<String>? = nil,
        read: @escaping @MainActor @Sendable (Object) -> ModelValue?,
        write: @escaping @MainActor @Sendable (Object, ModelValue?, [String: ModelValue]) -> Void
    ) -> ModelField {
        var field = ModelField(
            key: key, kind: kind,
            source: .computed(ModelFieldCode(
                read: { object in (object as? Object).flatMap(read) },
                write: { object, value, row in
                    guard let object = object as? Object else { return }
                    write(object, value, row)
                }
            )),
            required: required, filled: false, keptWhenMissing: kept
        )
        field.dropsRecordWhenMissing = dropsRecordWhenMissing
        field.defaultWhenMissing = defaultWhenMissing
        field.allowedStrings = allowedStrings
        return field
    }

    /// A string attribute whose values are an enum's raw values, written
    /// through the typed accessor (`read`, which reads a bad raw as its
    /// fallback) and restored as `fallback` when the row's isn't one.
    static func raw<Object: NSManagedObject, Value: RawRepresentable<String>>(
        _ key: String,
        attribute: String? = nil,
        of type: Object.Type,
        read: @escaping @MainActor @Sendable (Object) -> Value,
        fallback: Value,
        kept: Bool = false
    ) -> ModelField where Value: Sendable {
        let attribute = attribute ?? key
        return computed(
            key, .string, of: type, required: !kept, kept: kept,
            read: { .string(read($0).rawValue) },
            write: { object, value, _ in
                guard case .string(let raw)? = value else { return }
                object.setValue((Value(rawValue: raw) ?? fallback).rawValue, forKey: attribute)
            }
        )
    }

    /// A string attribute holding an enum's raw value, written as stored (a
    /// bad raw goes out as it is) and restored through `normalized`, the old
    /// importers' `Enum(rawValue:) ?? fallback`. A `kept` one may be missing
    /// from a row, which then leaves the record's own.
    static func storedRaw<Object: NSManagedObject>(
        _ key: String,
        of type: Object.Type,
        kept: Bool = false,
        defaultWhenMissing: ModelValue? = nil,
        restoring normalized: @escaping @MainActor @Sendable (String) -> String
    ) -> ModelField {
        computed(
            key, .string, of: type, required: !kept, kept: kept, defaultWhenMissing: defaultWhenMissing,
            read: { ($0.value(forKey: key) as? String).map(ModelValue.string) },
            write: { object, value, _ in
                guard case .string(let raw)? = value else { return }
                object.setValue(normalized(raw), forKey: key)
            }
        )
    }
}

/// The code behind a computed field.
nonisolated public struct ModelFieldCode: Sendable {
    let read: @MainActor @Sendable (NSManagedObject) -> ModelValue?
    let write: @MainActor @Sendable (NSManagedObject, ModelValue?, [String: ModelValue]) -> Void
}

/// How the restore re-links a row to its parent.
nonisolated public struct ParentLink: Sendable {
    /// What happens when the parent can't be found.
    public enum Missing: Sendable {
        /// Leave the relationship as it is (a new record keeps it unset).
        case keep
        /// Set the relationship to nil when the key holds an id that isn't
        /// found; keep it when the key isn't an id at all.
        case clearWhenNotFound
        /// Always set it: to the parent found by that id, or to nil.
        case alwaysSet
    }

    /// The row key holding the parent's id: an attribute (a UUID string) or a
    /// `.parentID` key (a UUID).
    let key: String
    let relationship: String
    let missing: Missing
    /// Re-linked once every type is in, not as the row is restored: a note's
    /// parents are restored after it. The relationship is set to the parent
    /// found by the row's id, or nil (`BackupEntityImporter.relinkDeferred`).
    let deferred: Bool

    public init(key: String, relationship: String, missing: Missing = .keep, deferred: Bool = false) {
        self.key = key
        self.relationship = relationship
        self.missing = missing
        self.deferred = deferred
    }
}
