import Foundation
import CoreData
import CloudKit

@objc(ClassroomMembership)
nonisolated public class CDClassroomMembership: NSManagedObject {
    // MARK: - Enums
    enum ClassroomRole: String, Codable, CaseIterable, Sendable {
        case leadGuide
        case assistant
    }

    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var classroomZoneID: String
    @NSManaged public var roleRaw: String
    @NSManaged public var ownerIdentity: String
    @NSManaged public var joinedAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ClassroomMembership", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.classroomZoneID = ""
        self.roleRaw = ClassroomRole.leadGuide.rawValue
        self.ownerIdentity = ""
        self.joinedAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

nonisolated extension CDClassroomMembership {
    var role: ClassroomRole {
        get { ClassroomRole(rawValue: roleRaw) ?? .leadGuide }
        set { roleRaw = newValue.rawValue }
    }

    /// This device's membership row — the one row every reader uses.
    ///
    /// Several rows can exist (a notebook that shared, stopped, and shared
    /// again; rows synced from the guide's other devices). The current one is
    /// the most recently pinned: newest `modifiedAt`, then newest `joinedAt`.
    /// Before 2026-09-28 the role and the share were read from the oldest row
    /// while the repository read the newest, so they could disagree.
    static func current(in context: NSManagedObjectContext) -> CDClassroomMembership? {
        let request = ownRowsRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "modifiedAt", ascending: false),
            NSSortDescriptor(key: "joinedAt", ascending: false)
        ]
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    /// The device's role, read from the current membership row. A notebook
    /// with no membership yet (solo use, before any share exists) is its own
    /// lead guide.
    static func currentRole(in context: NSManagedObjectContext) -> ClassroomRole {
        current(in: context)?.role ?? .leadGuide
    }

    /// The zone of the one classroom share: the pin. Written when the lead
    /// guide sets up (or re-sets up) sharing and when an assistant accepts an
    /// invitation. Nil means the classroom isn't shared yet.
    static func pinnedZoneName(in context: NSManagedObjectContext) -> String? {
        guard let zone = current(in: context)?.classroomZoneID, !zone.isEmpty else { return nil }
        return zone
    }

    /// The classroom's share among the shares a store holds: the one whose
    /// zone is pinned, and nothing else.
    ///
    /// It used to fall back to `.first` when nothing matched. A store can hold
    /// several shares and `fetchShares(in:)` returns them in no order, so the
    /// guess sent invitations to empty zones and filed new records into
    /// whichever zone came first — how one classroom ended up spread over
    /// five. No pin, or no share matching it, now means "not shared yet".
    static func classroomShare(among shares: [CKShare], in context: NSManagedObjectContext) -> CKShare? {
        guard let zone = pinnedZoneName(in: context) else { return nil }
        return shares.first { $0.recordID.zoneID.zoneName == zone }
    }

    /// The membership rows this app may read as "who I am".
    ///
    /// Membership rows live in the private store (never the classroom share),
    /// so they sync to every app and device on the same Apple Account. The companion app would therefore also
    /// see the rows the full notebook writes for that account — a lead guide's
    /// row, if the assistant keeps a notebook of their own — and would then file
    /// attendance as a lead guide, where the guide never sees it. The companion
    /// only ever joins as an assistant, so it reads assistant rows alone.
    static func ownRowsRequest() -> NSFetchRequest<CDClassroomMembership> {
        let request = CDFetchRequest(CDClassroomMembership.self)
        #if ASSISTANT_APP
        request.predicate = NSPredicate(format: "roleRaw == %@", ClassroomRole.assistant.rawValue)
        #endif
        return request
    }
}
