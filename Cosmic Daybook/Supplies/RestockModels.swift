// RestockModels.swift
// A staple's level, where a need is filled from, and who made a change.

import CoreData
import Foundation

/// How much of a staple is on the shelf (`CDSupply.levelRaw`). Low and Out
/// each give the staple one open need (`RestockService`).
nonisolated enum RestockLevel: String, CaseIterable, Identifiable, Sendable {
    case stocked
    case low
    case out

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stocked: "Stocked"
        case .low: "Low"
        case .out: "Out"
        }
    }

    /// Low and Out put the staple on the office run or the to-order list.
    var isNeeded: Bool { self != .stocked }

    /// Where a tap on a staple's tile goes: Stocked → Low → Out. Out goes back
    /// to Stocked only from a check-off or the menu, so a tap there returns nil
    /// and the screen shows a hint instead.
    var afterTap: RestockLevel? {
        switch self {
        case .stocked: .low
        case .low: .out
        case .out: nil
        }
    }
}

/// Where a need is filled from: fetched from the school office, or ordered
/// (`CDSupply.sourceRaw`, `CDOrderItem.sourceRaw`). A need from the office
/// goes only To Request → Received; asking for it and confirming it are for
/// orders.
nonisolated enum RestockSource: String, CaseIterable, Identifiable, Sendable {
    case office
    case order

    var id: String { rawValue }
}

/// Who is making a change, for the who-and-when that staples and needs carry.
///
/// Stamped the way attendance marks are (`CDAttendanceStore`): the CloudKit
/// record name always, a name only for an assistant. The guide's own changes
/// read as "You" on the guide's devices and, on an assistant's, as the name he
/// set for himself (`names`), else "your guide".
nonisolated struct RestockAuthor: Sendable, Equatable {
    var role: CDClassroomMembership.ClassroomRole
    /// This person's CloudKit user record name, when known.
    var recordName: String?
    /// The name an assistant typed on her phone.
    var name: String?
    /// On an assistant's phone, the classroom owner's CloudKit record name:
    /// whose unnamed changes are her guide's. Nil when not known.
    var ownerRecordName: String?
    /// The names people set for themselves (`ClassroomNames.snapshot`), for
    /// reading changes only: the person's current name beats the one stamped,
    /// so a rename reaches old entries. Never stamped on anything.
    var names: ClassroomNames.Snapshot

    init(
        role: CDClassroomMembership.ClassroomRole,
        recordName: String? = nil,
        name: String? = nil,
        ownerRecordName: String? = nil,
        names: ClassroomNames.Snapshot = ClassroomNames.Snapshot()
    ) {
        self.role = role
        // A stand-in such as `__defaultOwner__` names nobody in particular.
        self.recordName = ClassroomIdentity.realRecordName(recordName)
        self.name = name
        self.ownerRecordName = ClassroomIdentity.realRecordName(ownerRecordName)
        self.names = names
    }

    /// This author, reading changes with `names`.
    func reading(_ names: ClassroomNames.Snapshot) -> RestockAuthor {
        var author = self
        author.names = names
        return author
    }

    /// This device's user in `role`, as `ClassroomIdentity` knows them.
    @MainActor
    static func current(role: CDClassroomMembership.ClassroomRole) -> RestockAuthor {
        RestockAuthor(
            role: role,
            recordName: ClassroomIdentity.currentUserRecordName,
            name: role == .assistant ? ClassroomIdentity.displayName : nil
        )
    }

    /// This phone's assistant as she is now, with her classroom's owner as
    /// her membership row names them (`ownerIdentity`, written when she
    /// joined).
    @MainActor
    static func assistant(in context: NSManagedObjectContext) -> RestockAuthor {
        var author = current(role: .assistant)
        // "unknown" and "self" stand in where the share gave no record name.
        let owner = CDClassroomMembership.current(in: context)?.ownerIdentity
        author.ownerRecordName = ClassroomIdentity.realRecordName(owner)
        return author
    }

    /// This device's user, in the role its classroom membership gives it.
    @MainActor
    static func current(in context: NSManagedObjectContext) -> RestockAuthor {
        current(role: CDClassroomMembership.currentRole(in: context))
    }

    /// The name a change is stamped with: an assistant's, never the guide's.
    var stampedName: String {
        role == .assistant ? (name?.trimmed() ?? "") : ""
    }

    /// Who made a change, as this person reads it: "You" for their own; else
    /// the name the person goes by now (`names`, looked up by the stamp's ID),
    /// then the name an assistant was stamped with; on an assistant's phone the
    /// guide's name for the guide's changes (which carry no name), else "your
    /// guide"; and for one who gave no name "another assistant" there (told
    /// from the guide by `ownerRecordName`) and "an assistant" on the guide's
    /// devices. A stamp holding a stand-in (`ClassroomIdentity.realRecordName`)
    /// reads as having no ID.
    func reads(changedByID stampedID: String?, name: String?) -> String {
        let id = ClassroomIdentity.realRecordName(stampedID)
        if let id, let mine = recordName, id == mine { return "You" }
        // Before this device knows its record name: a classroom has one lead
        // guide, so on his devices a lead guide's row is his own.
        if recordName == nil, role == .leadGuide, names.role(forRecordName: id) == .leadGuide { return "You" }
        let current = names.name(forRecordName: id)
        let name = name?.trimmed() ?? ""
        if !name.isEmpty {
            // Her own change from a phone that had no record name yet.
            if role == .assistant, name == self.name?.trimmed(), id == nil || recordName == nil { return "You" }
            return current ?? name
        }
        if let current {
            // Her own unnamed change from a phone with no record name yet.
            if role == .assistant, recordName == nil, current == self.name?.trimmed() { return "You" }
            return current
        }
        if role == .assistant {
            // Without the owner's record name, an unnamed change is most
            // likely the guide's, as it always read before.
            if let id, let owner = ownerRecordName, id != owner { return "another assistant" }
            return names.guideName ?? "your guide"
        }
        if let id, let mine = recordName, id != mine { return "an assistant" }
        return "You"
    }
}

/// A line of a staple's history as both apps' history sheets show it, naming
/// whoever made the change by the name they go by now.
///
/// A level change's `reason` is written as "Low · Ana", the name stamped then,
/// which older builds show as is; from schema 17 the line also carries who made
/// it (`CDSupplyTransaction.changedByID`). A newer build keeps what happened
/// ("Low") and adds the person's current name (`names`), so a rename reaches
/// old lines too. Without a current name the line reads as stamped; lines from
/// before schema 17 (no ID) and counted changes read as written.
nonisolated enum RestockHistoryLine {
    static let separator = " · "

    static func text(reason: String, changedByID: String?, names: ClassroomNames.Snapshot) -> String {
        let reason = reason.trimmed()
        guard !reason.isEmpty, let current = names.name(forRecordName: changedByID) else { return reason }
        let what = reason.range(of: separator).map { String(reason[..<$0.lowerBound]) } ?? reason
        return what + separator + current
    }
}
