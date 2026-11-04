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

/// A backed-up entity type written and read through `ModelRow`.
nonisolated public protocol ModelRowKind: Sendable {
    static var spec: ModelRowSpec { get }
}

/// The per-type facts about a `ModelRow` entity; everything else comes from the model.
nonisolated public struct ModelRowSpec: Sendable {
    let entityName: String
    /// Every key but `id`: the attributes in model order, then the computed
    /// fields, then the parent ids.
    let fields: [ModelField]
    let parents: [ParentLink]
    /// The export skips a record whose `id` is nil instead of giving it a new one.
    let dropsRecordsWithoutID: Bool
    /// Whether the restore takes a row at all (the old importers' `guard`s);
    /// nil takes every row.
    let restoresRow: (@Sendable ([String: ModelValue]) -> Bool)?

    /// - Parameters:
    ///   - filling: optional attributes the export fills when nil.
    ///   - omitting: attributes never backed up (device-local blobs), and
    ///     those a computed field carries under another key.
    ///   - addedLater: attributes a row may lack that the restore then leaves
    ///     as they are: non-optional ones added after the type's first format
    ///     (an older backup's rows lack them, so they aren't required; a new
    ///     record's is the model's default), and optional ones the old
    ///     importer set only when the row had them.
    ///   - renaming: row key → the attribute it carries, where they differ.
    ///   - uuidStrings: string attributes carried as UUIDs.
    ///   - requiring: attributes every row has; a record without one (or, for
    ///     a `uuidStrings` key, without a valid id) isn't backed up.
    ///   - defaults: what a row lacking the key reads as.
    ///   - computed: fields read and written by code; one replaces an
    ///     attribute's field of the same key.
    ///   - parentIDs: key → to-one relationship whose parent's id is written under the key.
    ///   - parents: how the restore re-links each parent.
    init(
        _ entityName: String,
        filling: Set<String> = [],
        omitting: Set<String> = [],
        addedLater: Set<String> = [],
        renaming: [String: String] = [:],
        uuidStrings: Set<String> = [],
        requiring: Set<String> = [],
        defaults: [String: ModelValue] = [:],
        computed: [ModelField] = [],
        parentIDs: [String: String] = [:],
        parents: [ParentLink] = [],
        dropsRecordsWithoutID: Bool = false,
        restoresRow: (@Sendable ([String: ModelValue]) -> Bool)? = nil
    ) {
        guard let attributes = BackupModelSchema.attributes[entityName] else {
            preconditionFailure("Backup row spec for \(entityName), which is not in the model")
        }
        let keyOfAttribute = Dictionary(uniqueKeysWithValues: renaming.map { ($0.value, $0.key) })
        let computedKeys = Set(computed.map(\.key))
        let attributeKeys = Set(attributes.map { keyOfAttribute[$0.name] ?? $0.name })
        let named = filling.union(addedLater).union(uuidStrings).union(requiring).union(defaults.keys)
        for key in named.subtracting(attributeKeys).subtracting(computedKeys) {
            preconditionFailure("Backup row spec for \(entityName) names \(key), which is not one of its keys")
        }
        for name in omitting.union(renaming.values) where !attributes.contains(where: { $0.name == name }) {
            preconditionFailure("Backup row spec for \(entityName) names \(name), which is not an attribute")
        }
        var fields: [ModelField] = attributes.compactMap { attribute in
            let key = keyOfAttribute[attribute.name] ?? attribute.name
            guard attribute.name != "id", !omitting.contains(attribute.name), !computedKeys.contains(key) else {
                return nil
            }
            let isLater = addedLater.contains(key)
            let isRequired = !attribute.isOptional || filling.contains(key) || requiring.contains(key)
            let carriesID = uuidStrings.contains(key)
            var field = ModelField(
                key: key,
                kind: carriesID ? .uuid : Self.kind(of: attribute.type, entity: entityName, name: attribute.name),
                source: .attribute(attribute.name),
                required: isRequired && !isLater,
                filled: filling.contains(key),
                keptWhenMissing: isLater
            )
            field.storedAsString = carriesID
            field.dropsRecordWhenMissing = requiring.contains(key)
            field.defaultWhenMissing = defaults[key]
            return field
        }
        fields += computed
        for (key, relationship) in parentIDs.sorted(by: { $0.key < $1.key }) {
            fields.append(ModelField(
                key: key, kind: .uuid, source: .parentID(relationship: relationship), required: false, filled: false,
                keptWhenMissing: false
            ))
        }
        self.entityName = entityName
        self.fields = fields
        self.parents = parents
        self.dropsRecordsWithoutID = dropsRecordsWithoutID
        self.restoresRow = restoresRow
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
            var value: ModelValue?
            switch field.source {
            case .attribute(let attribute):
                let raw = object.value(forKey: attribute)
                value = field.storedAsString
                    ? (raw as? String).flatMap(UUID.init(uuidString:)).map(ModelValue.uuid)
                    : Self.value(raw, kind: field.kind)
            case .parentID(let relationship):
                let raw = (object.value(forKey: relationship) as? NSManagedObject)?.value(forKey: "id")
                value = Self.value(raw, kind: field.kind)
            case .computed(let code):
                value = code.read(object)
            }
            if value == nil, field.filled { value = Self.filler(for: field.kind) }
            if value == nil, field.dropsRecordWhenMissing { return nil }
            values[field.key] = value
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
        // Only computed fields carry these.
        case .uuids, .doubleArrays: return nil
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
            let isPresent = try container.contains(key) && !container.decodeNil(forKey: key)
            if !isPresent, let fallback = field.defaultWhenMissing {
                values[field.key] = fallback
                continue
            }
            // A required key that is missing or null throws here, as the DTO's did.
            guard field.required || isPresent else { continue }
            let value = try Self.decode(field.kind, key, in: container)
            if let allowed = field.allowedStrings, case .string(let text) = value, !allowed.contains(text) {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container, debugDescription: "\(text) is not one of \(field.key)'s values"
                )
            }
            values[field.key] = value
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
        case .uuids: .uuids(try container.decode([UUID].self, forKey: key))
        case .doubleArrays: .doubleArrays(try container.decode([[Double]].self, forKey: key))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(id, forKey: Key("id"))
        for (name, value) in values {
            try Self.encode(value, Key(name), in: &container)
        }
    }

    private static func encode(
        _ value: ModelValue, _ key: Key, in container: inout KeyedEncodingContainer<Key>
    ) throws {
        switch value {
        case .string(let value): try container.encode(value, forKey: key)
        case .int(let value): try container.encode(value, forKey: key)
        case .double(let value): try container.encode(value, forKey: key)
        case .bool(let value): try container.encode(value, forKey: key)
        case .date(let value): try container.encode(value, forKey: key)
        case .uuid(let value): try container.encode(value, forKey: key)
        case .strings(let value): try container.encode(value, forKey: key)
        case .data(let value): try container.encode(value, forKey: key)
        case .uuids(let value): try container.encode(value, forKey: key)
        case .doubleArrays(let value): try container.encode(value, forKey: key)
        }
    }
}

extension ModelRow: BackupRowDTO {}
