import CoreData
import Foundation

/// What a meeting card's Re-present or Ready for Next planned at the moment
/// of the tap, kept with the child's draft so the card, Rest or Clear can
/// take it back after a relaunch (domain logic review 2026-11-20, R8).
///
/// Both used to plan only at Complete, from a draft kept on one device: tap
/// Re-present on the iPad, finish on the Mac (or never), and the work stayed
/// closed with nothing planned and no undo. Now the plan is in the synced
/// store at once, and this receipt says how to take it back: the objects the
/// tap made, which are deleted, and every attribute it changed on the
/// objects it found, with the value before and after, which are put back.
/// Taking back refuses when anything has moved since (a plan scheduled or
/// given, a follow-up resolved another way), so a later change is never
/// undone by a meeting.
///
/// Object IDs are kept as URIs and the values as plain ones, as
/// `MeetingCloseToken` keeps its receipt.
nonisolated struct MeetingTapPlan: Codable, Equatable, Sendable {

    enum Kind: String, Codable, Sendable {
        /// Re-present: the lesson planned again as a second pass.
        case represent
        /// Ready for Next: confirmed on the lesson, the next one On Deck.
        case ready
    }

    /// An attribute value as stored.
    enum Value: Codable, Equatable, Sendable {
        case null
        case string(String)
        case date(Date)
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case uuid(UUID)
        case data(Data)
    }

    /// One attribute the tap set. `before` is nil on an object the tap made.
    struct Edit: Codable, Equatable, Sendable {
        var objectURI: URL
        var key: String
        var before: Value?
        var after: Value
    }

    var kind: Kind
    /// The lessons the tap planned (or found already planned), so Complete
    /// doesn't file a request for one of them again.
    var lessonIDs: [String] = []
    /// The objects the tap made: plans and history rows.
    var createdURIs: [URL] = []
    var edits: [Edit] = []

    var plannedLessonIDs: Set<UUID> { Set(lessonIDs.compactMap(UUID.init(uuidString:))) }
}

// MARK: - Making one

extension MeetingTapPlan {

    /// Runs `plan` and records what it made and changed in `context`. `plan`
    /// returns the lessons it planned. Nothing is saved.
    static func capture(
        _ kind: Kind, in context: NSManagedObjectContext, _ plan: () throws -> [UUID]
    ) rethrows -> MeetingTapPlan {
        context.processPendingChanges()
        let insertedBefore = context.insertedObjects
        var pendingBefore: [NSManagedObjectID: [String: Any]] = [:]
        for object in context.updatedObjects {
            pendingBefore[object.objectID] = object.changedValues()
        }

        let lessons = try plan()

        context.processPendingChanges()
        let created = Array(context.insertedObjects.subtracting(insertedBefore)).filter { !$0.isDeleted }
        try? context.obtainPermanentIDs(for: created)
        var result = MeetingTapPlan(kind: kind, lessonIDs: lessons.map(\.uuidString))
        for object in created where !object.objectID.isTemporaryID {
            let uri = object.objectID.uriRepresentation()
            result.createdURIs.append(uri)
            for (key, attribute) in object.entity.attributesByName {
                guard let after = value(object.value(forKey: key), as: attribute) else { continue }
                result.edits.append(Edit(objectURI: uri, key: key, before: nil, after: after))
            }
        }
        for object in context.updatedObjects where !object.isDeleted && !object.objectID.isTemporaryID {
            let attributes = object.entity.attributesByName
            let earlier = pendingBefore[object.objectID] ?? [:]
            for key in object.changedValues().keys {
                guard let attribute = attributes[key],
                      let after = value(object.value(forKey: key), as: attribute) else { continue }
                let beforeRaw: Any? = earlier.keys.contains(key)
                    ? earlier[key] : object.committedValues(forKeys: [key])[key]
                guard let before = value(beforeRaw, as: attribute), before != after else { continue }
                result.edits.append(Edit(
                    objectURI: object.objectID.uriRepresentation(), key: key, before: before, after: after
                ))
            }
        }
        return result
    }

    /// A stored value in plain form, or nil for a type a receipt can't keep.
    private static func value(_ raw: Any?, as attribute: NSAttributeDescription) -> Value? {
        guard let raw, !(raw is NSNull) else { return .null }
        switch attribute.attributeType {
        case .stringAttributeType: return (raw as? String).map(Value.string)
        case .dateAttributeType: return (raw as? Date).map(Value.date)
        case .booleanAttributeType: return (raw as? NSNumber).map { .bool($0.boolValue) }
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            return (raw as? NSNumber).map { .int($0.int64Value) }
        case .doubleAttributeType, .floatAttributeType:
            return (raw as? NSNumber).map { .double($0.doubleValue) }
        case .UUIDAttributeType: return (raw as? UUID).map(Value.uuid)
        case .binaryDataAttributeType: return (raw as? Data).map(Value.data)
        default: return nil
        }
    }
}

// MARK: - Taking it back

extension MeetingTapPlan {

    /// Whether everything the tap set is still as it left it. An object
    /// gone since (a plan deleted by hand) needs nothing taking back.
    func canTakeBack(in context: NSManagedObjectContext) -> Bool {
        edits.allSatisfy { edit in
            guard let object = Self.object(edit.objectURI, in: context) else { return true }
            guard let attribute = object.entity.attributesByName[edit.key] else { return true }
            return Self.same(Self.value(object.value(forKey: edit.key), as: attribute), edit.after)
        }
    }

    /// Equal, with dates within a millisecond: a draft's dates go through JSON
    /// (as `MeetingCloseToken.sameInstant` allows).
    private static func same(_ lhs: Value?, _ rhs: Value) -> Bool {
        if case .date(let left)? = lhs, case .date(let right) = rhs {
            return abs(left.timeIntervalSince(right)) < 0.001
        }
        return lhs == rhs
    }

    /// Puts back what the tap changed and deletes what it made, when nothing
    /// has moved since; returns false, changing nothing, otherwise. In memory
    /// only: the caller saves.
    @discardableResult
    func takeBack(in context: NSManagedObjectContext) -> Bool {
        guard canTakeBack(in: context) else { return false }
        let created = Set(createdURIs)
        for edit in edits where !created.contains(edit.objectURI) {
            guard let before = edit.before, let object = Self.object(edit.objectURI, in: context) else { continue }
            object.setValue(Self.raw(before), forKey: edit.key)
        }
        for uri in createdURIs {
            guard let object = Self.object(uri, in: context), !object.isDeleted else { continue }
            if let plan = object as? CDLessonAssignment {
                PresentationRecordCleanup.prepareToDelete(plan, in: context)
            }
            context.delete(object)
        }
        context.processPendingChanges()
        return true
    }

    private static func object(_ uri: URL, in context: NSManagedObjectContext) -> NSManagedObject? {
        guard let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri),
              let object = context.existing(id), !object.isDeleted else { return nil }
        return object
    }

    private static func raw(_ value: Value) -> Any? {
        switch value {
        case .null: nil
        case .string(let string): string
        case .date(let date): date
        case .bool(let bool): NSNumber(value: bool)
        case .int(let int): NSNumber(value: int)
        case .double(let double): NSNumber(value: double)
        case .uuid(let uuid): uuid
        case .data(let data): data
        }
    }
}
