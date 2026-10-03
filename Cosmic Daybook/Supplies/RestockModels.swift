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
/// read as "You" on the guide's devices and "your guide" on an assistant's.
nonisolated struct RestockAuthor: Sendable, Equatable {
    var role: CDClassroomMembership.ClassroomRole
    /// This person's CloudKit user record name, when known.
    var recordName: String?
    /// The name an assistant typed on her phone.
    var name: String?

    init(role: CDClassroomMembership.ClassroomRole, recordName: String? = nil, name: String? = nil) {
        self.role = role
        self.recordName = recordName
        self.name = name
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

    /// This device's user, in the role its classroom membership gives it.
    @MainActor
    static func current(in context: NSManagedObjectContext) -> RestockAuthor {
        current(role: CDClassroomMembership.currentRole(in: context))
    }

    /// The name a change is stamped with: an assistant's, never the guide's.
    var stampedName: String {
        role == .assistant ? (name?.trimmed() ?? "") : ""
    }

    /// Who made a change, as this person reads it: "You" for their own, the
    /// name an assistant gave, "your guide" on an assistant's phone for the
    /// guide's changes (which carry no name), and on the guide's devices
    /// "an assistant" for one who gave no name.
    func reads(changedByID id: String?, name: String?) -> String {
        if let id, let mine = recordName, id == mine { return "You" }
        let name = name?.trimmed() ?? ""
        if !name.isEmpty {
            // Her own change from a phone that had no record name yet.
            if role == .assistant, name == self.name?.trimmed(), id == nil || recordName == nil { return "You" }
            return name
        }
        if role == .assistant { return "your guide" }
        if let id, let mine = recordName, id != mine { return "an assistant" }
        return "You"
    }
}
