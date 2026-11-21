import Foundation
import CoreData
import SwiftUI

// MARK: - Core Data Entity

@objc(CDAttendanceRecord)
nonisolated public class CDAttendanceRecord: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var date: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var absenceReasonRaw: String
    /// `ClassroomRole` rawValue of whoever last marked this record (lead guide or assistant).
    @NSManaged public var recordedBy: String?
    /// Stable CloudKit user record name of the person who last marked this.
    /// The role alone can't separate one assistant from another.
    @NSManaged public var recordedByID: String?
    /// What that person calls themselves, captured on their own device —
    /// CloudKit withholds your own name from you, so it cannot be looked up.
    @NSManaged public var recordedByName: String?
    @NSManaged public var modifiedAt: Date?
    /// When the current status was set: "arrived 8:12". For Left Early it is
    /// the arrival, kept from the present or tardy mark before it. Unlike
    /// `modifiedAt`, a note edit leaves it alone. Nil while unmarked, on
    /// records marked before it existed, and on marks made on any day but the
    /// one they're for. Written by `CDAttendanceStore` with the status.
    @NSManaged public var markedAt: Date?
    /// When a child marked Left Early went home: "8:02 → 1:15". `markedAt`
    /// keeps the arrival. A child brought back (Back in Class) keeps it too,
    /// as the start of the trip out. Nil for every other mark, and for marks
    /// made on any day but the one they're for. Written by `CDAttendanceStore`.
    @NSManaged public var leftAt: Date?
    /// When a child who left early came back: "out 11:15–12:40" with
    /// `leftAt`. Set only by Back in Class; any other mark clears it.
    /// Written by `CDAttendanceStore.markBack`.
    @NSManaged public var returnedAt: Date?
    /// The status a Left Early child left from, present or tardy, so Back in
    /// Class returns them to it. Nil for every other status. Written by
    /// `CDAttendanceStore` with the status.
    @NSManaged public var statusBeforeLeavingRaw: String?
    /// When the child is due to be picked up early: "leaves 1:30". A plan,
    /// not a mark: set ahead from the tile's menu, it leaves the status alone,
    /// and `leftAt` still records when they actually went. Written by
    /// `CDAttendanceStore.updateLeavesAt`.
    @NSManaged public var leavesAt: Date?
    /// The day's attendance note ("dentist, back by 11"). It lives on the
    /// record, not in the private notes, so the guide and an assistant share
    /// it; write it through `CDAttendanceStore.updateNote`.
    @NSManaged public var note: String?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AttendanceRecord", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.date = Date()
        self.statusRaw = AttendanceStatus.unmarked.rawValue
        self.absenceReasonRaw = AbsenceReason.none.rawValue
    }
}

// MARK: - Computed Properties

nonisolated extension CDAttendanceRecord {
    // Computed enum mapping for convenient UI usage
    var status: AttendanceStatus {
        get { AttendanceStatus(rawValue: statusRaw) ?? .unmarked }
        set {
            statusRaw = newValue.rawValue
            // Clear absence reason if status is not absent
            if newValue != .absent {
                absenceReasonRaw = AbsenceReason.none.rawValue
            }
        }
    }

    /// Whether the child arrived late that day: marked tardy, or Left Early
    /// after arriving late (`statusBeforeLeavingRaw`). The tardy figures
    /// count both, so going home early doesn't erase a late arrival.
    var cameLate: Bool {
        status == .tardy
            || (status == .leftEarly && statusBeforeLeavingRaw == AttendanceStatus.tardy.rawValue)
    }

    /// Whether the child arrived on time and then left early: Left Early
    /// from Present.
    var leftAfterOnTime: Bool {
        status == .leftEarly && statusBeforeLeavingRaw == AttendanceStatus.present.rawValue
    }

    // Computed property for absence reason
    var absenceReason: AbsenceReason {
        get { AbsenceReason(rawValue: absenceReasonRaw) ?? .none }
        set { absenceReasonRaw = newValue.rawValue }
    }

    // Computed property for backward compatibility with UUID
    var studentIDUUID: UUID? {
        get { UUID(uuidString: studentID) }
        set { studentID = newValue?.uuidString ?? "" }
    }
}

// MARK: - Paired fields

nonisolated extension CDAttendanceRecord {
    /// Whether the fields that belong to one status disagree with it
    /// (`normalize` would change something).
    var hasMismatchedFields: Bool { pairFixes(apply: false) }

    /// Puts the fields that belong to one status right, as
    /// `CDAttendanceStore` writes them: a reason only on an absence, the
    /// status left from only on a Left Early (and only present or late),
    /// no times on an unmarked record, no trip out on an absence or a Left
    /// Early, and a return only after a time out. A restore or an import
    /// writes the fields one by one and could keep an odd pair, such as a
    /// present mark with an old "Sick" (domain-logic review A13). The note
    /// and a planned pickup belong to any status and stay. A status this
    /// build doesn't know (a newer build's) is left alone, as is
    /// `modifiedAt`: this is no one's change. Returns whether it changed.
    @discardableResult
    func normalize() -> Bool { pairFixes(apply: true) }

    private func pairFixes(apply: Bool) -> Bool {
        guard let status = AttendanceStatus(rawValue: statusRaw) else { return false }
        var changed = false
        func clear<Value>(_ path: ReferenceWritableKeyPath<CDAttendanceRecord, Value?>) {
            guard self[keyPath: path] != nil else { return }
            changed = true
            if apply { self[keyPath: path] = nil }
        }
        if status != .absent, absenceReasonRaw != AbsenceReason.none.rawValue {
            changed = true
            if apply { absenceReasonRaw = AbsenceReason.none.rawValue }
        }
        let leftFrom = [AttendanceStatus.present.rawValue, AttendanceStatus.tardy.rawValue]
        if status != .leftEarly || !leftFrom.contains(statusBeforeLeavingRaw ?? leftFrom[0]) {
            clear(\.statusBeforeLeavingRaw)
        }
        switch status {
        case .unmarked:
            clear(\.markedAt)
            clear(\.leftAt)
            clear(\.returnedAt)
        case .absent:
            clear(\.leftAt)
            clear(\.returnedAt)
        case .leftEarly:
            clear(\.returnedAt)
        case .present, .tardy:
            if leftAt == nil { clear(\.returnedAt) }
        }
        return changed
    }

    /// `normalize()` on every attendance record `context` holds; returns
    /// how many changed. For after a restore, whose rows come field by
    /// field. The caller saves.
    @discardableResult
    static func normalizeAll(in context: NSManagedObjectContext) -> Int {
        context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).count { $0.normalize() }
    }
}
