// ModelRow.swift
// Backup rows for the entity types whose backup is a straight copy of their
// Core Data attributes, read from the model instead of hand-written per type.
//
// Each such type is a `ModelRowKind` with a short spec (Backup/ModelRowKinds.swift),
// and its old DTO name is an alias of `ModelRow<Kind>`, so the payload, the
// entity table and the preview still name it the same way. A row carries every
// attribute of its entity under the attribute's own name, plus at most a
// parent's id; which keys are required, which the export fills when the
// attribute is nil, and how a parent is re-linked on restore are the only
// per-type facts, and they are exactly what the hand-written DTOs, transformers
// and importers encoded. `BackupGoldenOutputTests` pins the bytes: a backup
// written through these rows is identical to one written through the DTOs.

import CoreData
import Foundation
import OSLog

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
        }
    }
}

/// One key of a backup row.
nonisolated public struct ModelField: Sendable {
    public enum Kind: Sendable {
        case string, int, double, bool, date, uuid, strings, data
    }

    /// Where the value comes from and goes to.
    public enum Source: Sendable {
        /// The model attribute of the same name.
        case attribute
        /// The `id` of the parent reached through this to-one relationship.
        /// Written on export; the restore re-links through `ParentLink`.
        case parentID(relationship: String)
    }

    let key: String
    let kind: Kind
    let source: Source
    /// Every row has it: the attribute is non-optional, or the export fills it.
    let required: Bool
    /// The export writes a made-up value when the attribute is nil: a new id,
    /// the current time, or an empty list.
    let filled: Bool
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

    public init(key: String, relationship: String, missing: Missing = .keep) {
        self.key = key
        self.relationship = relationship
        self.missing = missing
    }
}

/// A backed-up entity type written and read through `ModelRow`.
nonisolated public protocol ModelRowKind: Sendable {
    static var spec: ModelRowSpec { get }
}

/// The per-type facts about a `ModelRow` entity; everything else comes from the model.
nonisolated public struct ModelRowSpec: Sendable {
    let entityName: String
    /// Every key but `id`, in model order.
    let fields: [ModelField]
    let parents: [ParentLink]
    /// The export skips a record whose `id` is nil instead of giving it a new one.
    let dropsRecordsWithoutID: Bool

    /// - Parameters:
    ///   - filling: optional attributes the export fills when nil.
    ///   - omitting: attributes never backed up (device-local blobs).
    ///   - parentIDs: key → to-one relationship whose parent's id is written under the key.
    ///   - parents: how the restore re-links each parent.
    init(
        _ entityName: String,
        filling: Set<String> = [],
        omitting: Set<String> = [],
        parentIDs: [String: String] = [:],
        parents: [ParentLink] = [],
        dropsRecordsWithoutID: Bool = false
    ) {
        guard let attributes = BackupModelSchema.attributes[entityName] else {
            preconditionFailure("Backup row spec for \(entityName), which is not in the model")
        }
        var fields: [ModelField] = attributes.compactMap { attribute in
            guard attribute.name != "id", !omitting.contains(attribute.name) else { return nil }
            return ModelField(
                key: attribute.name,
                kind: Self.kind(of: attribute.type, entity: entityName, name: attribute.name),
                source: .attribute,
                required: !attribute.isOptional || filling.contains(attribute.name),
                filled: filling.contains(attribute.name)
            )
        }
        for (key, relationship) in parentIDs.sorted(by: { $0.key < $1.key }) {
            fields.append(ModelField(
                key: key, kind: .uuid, source: .parentID(relationship: relationship), required: false, filled: false
            ))
        }
        self.entityName = entityName
        self.fields = fields
        self.parents = parents
        self.dropsRecordsWithoutID = dropsRecordsWithoutID
    }

    private static func kind(of type: NSAttributeType, entity: String, name: String) -> ModelField.Kind {
        switch type {
        case .stringAttributeType: .string
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: .int
        case .doubleAttributeType, .floatAttributeType: .double
        case .booleanAttributeType: .bool
        case .dateAttributeType: .date
        case .UUIDAttributeType: .uuid
        // The model's transformables are string arrays.
        case .transformableAttributeType: .strings
        case .binaryDataAttributeType: .data
        default: preconditionFailure("\(entity).\(name): attribute type \(type.rawValue) has no backup row form")
        }
    }
}

/// The attributes of every entity, read once from the app's compiled model. A
/// copy of its own: the app's shared model is main-actor state, and rows are
/// encoded and decoded off the main actor.
nonisolated enum BackupModelSchema {
    struct Attribute: Sendable {
        let name: String
        let type: NSAttributeType
        let isOptional: Bool
    }

    static let attributes: [String: [Attribute]] = {
        guard let url = Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            preconditionFailure("Backup rows need the \(CoreDataStack.modelName) model")
        }
        var result: [String: [Attribute]] = [:]
        for entity in model.entities {
            guard let name = entity.name else { continue }
            result[name] = entity.attributesByName.values
                .sorted { $0.name < $1.name }
                .map { Attribute(name: $0.name, type: $0.attributeType, isOptional: $0.isOptional) }
        }
        return result
    }()
}

/// One backed-up record of a `ModelRowKind` entity: its `id` and a value per key.
nonisolated public struct ModelRow<Kind: ModelRowKind>: Codable, Sendable {
    public var id: UUID
    public var values: [String: ModelValue]

    public init(id: UUID, values: [String: ModelValue]) {
        self.id = id
        self.values = values
    }

    /// The string under `key`, for code that reads one field of a row.
    func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { value } else { nil }
    }

    // MARK: Export

    /// The record as a row, or nil for a record the spec drops (no `id`).
    @MainActor
    init?(_ object: NSManagedObject) {
        let spec = Kind.spec
        if let id = object.value(forKey: "id") as? UUID {
            self.id = id
        } else if spec.dropsRecordsWithoutID {
            return nil
        } else {
            self.id = UUID()
        }
        var values: [String: ModelValue] = [:]
        for field in spec.fields {
            let raw: Any?
            switch field.source {
            case .attribute:
                raw = object.value(forKey: field.key)
            case .parentID(let relationship):
                raw = (object.value(forKey: relationship) as? NSManagedObject)?.value(forKey: "id")
            }
            if let value = Self.value(raw, kind: field.kind) {
                values[field.key] = value
            } else if field.filled {
                values[field.key] = Self.filler(for: field.kind)
            }
        }
        self.values = values
    }

    /// Every record as a row, in order; the entity table's export transform.
    @MainActor
    static func rows<Object: NSManagedObject>(_ objects: [Object]) -> [ModelRow] {
        objects.compactMap { ModelRow($0) }
    }

    private static func value(_ raw: Any?, kind: ModelField.Kind) -> ModelValue? {
        guard let raw, !(raw is NSNull) else { return nil }
        switch kind {
        case .string: return (raw as? String).map(ModelValue.string)
        case .int: return (raw as? NSNumber).map { .int($0.intValue) }
        case .double: return (raw as? NSNumber).map { .double($0.doubleValue) }
        case .bool: return (raw as? NSNumber).map { .bool($0.boolValue) }
        case .date: return (raw as? Date).map(ModelValue.date)
        case .uuid: return (raw as? UUID).map(ModelValue.uuid)
        case .strings: return (raw as? [String]).map(ModelValue.strings)
        case .data: return (raw as? Data).map(ModelValue.data)
        }
    }

    /// What the hand-written transformers wrote for a nil they had to fill.
    private static func filler(for kind: ModelField.Kind) -> ModelValue? {
        switch kind {
        case .date: .date(Date())
        case .uuid: .uuid(UUID())
        case .strings: .strings([])
        default: nil
        }
    }

    // MARK: Codable (the DTOs' synthesized form: required keys must be present, nil keys are left out)

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        id = try container.decode(UUID.self, forKey: Key("id"))
        var values: [String: ModelValue] = [:]
        for field in Kind.spec.fields {
            let key = Key(field.key)
            guard field.required || container.contains(key) else { continue }
            if !field.required, try container.decodeNil(forKey: key) { continue }
            values[field.key] = try Self.decode(field.kind, key, in: container)
        }
        self.values = values
    }

    private static func decode(
        _ kind: ModelField.Kind, _ key: Key, in container: KeyedDecodingContainer<Key>
    ) throws -> ModelValue {
        switch kind {
        case .string: .string(try container.decode(String.self, forKey: key))
        case .int: .int(try container.decode(Int.self, forKey: key))
        case .double: .double(try container.decode(Double.self, forKey: key))
        case .bool: .bool(try container.decode(Bool.self, forKey: key))
        case .date: .date(try container.decode(Date.self, forKey: key))
        case .uuid: .uuid(try container.decode(UUID.self, forKey: key))
        case .strings: .strings(try container.decode([String].self, forKey: key))
        case .data: .data(try container.decode(Data.self, forKey: key))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: Key("id"))
        for (name, value) in values {
            let key = Key(name)
            switch value {
            case .string(let value): try container.encode(value, forKey: key)
            case .int(let value): try container.encode(value, forKey: key)
            case .double(let value): try container.encode(value, forKey: key)
            case .bool(let value): try container.encode(value, forKey: key)
            case .date(let value): try container.encode(value, forKey: key)
            case .uuid(let value): try container.encode(value, forKey: key)
            case .strings(let value): try container.encode(value, forKey: key)
            case .data(let value): try container.encode(value, forKey: key)
            }
        }
    }
}

extension ModelRow: BackupRowDTO {}
