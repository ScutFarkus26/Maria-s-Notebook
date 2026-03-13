// GoingOutModel.swift
// SwiftData model for student-initiated going-out (field trip) excursions.
// CloudKit compatible: string FKs, raw string enums, modifiedAt.

import Foundation
import SwiftData
import SwiftUI

@Model
final class GoingOut: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var title: String = ""
    var purpose: String = ""
    var destination: String = ""
    var proposedDate: Date?
    var actualDate: Date?

    /// Status stored as raw string (CloudKit compatible)
    var statusRaw: String = GoingOutStatus.proposed.rawValue

    /// JSON-encoded student ID strings (CloudKit compatible)
    var studentIDs: [String] = []

    /// Comma-separated lesson UUID strings for curriculum connections
    var curriculumLinkIDs: String = ""

    /// Parent permission status stored as raw string
    var permissionStatusRaw: String = PermissionStatus.pending.rawValue

    /// Free-form notes about the going-out
    var notes: String = ""

    /// Follow-up work description
    var followUpWork: String = ""

    /// Teacher who proposed/approved
    var supervisorName: String = ""

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \GoingOutChecklistItem.goingOut)
    var checklistItems: [GoingOutChecklistItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Note.goingOut)
    var observationNotes: [Note]? = []

    // MARK: - Computed Properties

    @Transient
    var status: GoingOutStatus {
        get { GoingOutStatus(rawValue: statusRaw) ?? .proposed }
        set { statusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    @Transient
    var permissionStatus: PermissionStatus {
        get { PermissionStatus(rawValue: permissionStatusRaw) ?? .pending }
        set { permissionStatusRaw = newValue.rawValue; modifiedAt = Date() }
    }

    @Transient
    var studentUUIDs: [UUID] {
        get { studentIDs.compactMap { UUID(uuidString: $0) } }
        set { studentIDs = newValue.map(\.uuidString) }
    }

    @Transient
    var curriculumLinkUUIDs: [UUID] {
        get {
            curriculumLinkIDs
                .components(separatedBy: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set {
            curriculumLinkIDs = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    @Transient
    var sortedChecklistItems: [GoingOutChecklistItem] {
        (checklistItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        title: String = "",
        purpose: String = "",
        destination: String = "",
        proposedDate: Date? = nil,
        statusRaw: String = GoingOutStatus.proposed.rawValue,
        studentIDs: [String] = [],
        curriculumLinkIDs: String = "",
        permissionStatusRaw: String = PermissionStatus.pending.rawValue,
        notes: String = "",
        followUpWork: String = "",
        supervisorName: String = ""
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.destination = destination
        self.proposedDate = proposedDate
        self.statusRaw = statusRaw
        self.studentIDs = studentIDs
        self.curriculumLinkIDs = curriculumLinkIDs
        self.permissionStatusRaw = permissionStatusRaw
        self.notes = notes
        self.followUpWork = followUpWork
        self.supervisorName = supervisorName
    }
}

// MARK: - Status Enums

enum GoingOutStatus: String, CaseIterable, Identifiable, Codable {
    case proposed
    case planning
    case approved
    case completed
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proposed: return "Proposed"
        case .planning: return "Planning"
        case .approved: return "Approved"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .proposed: return "lightbulb"
        case .planning: return "list.clipboard"
        case .approved: return "checkmark.seal"
        case .completed: return "flag.checkered"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .proposed: return .blue
        case .planning: return .orange
        case .approved: return .green
        case .completed: return .purple
        case .cancelled: return .gray
        }
    }
}

enum PermissionStatus: String, CaseIterable, Identifiable, Codable {
    case pending
    case sent
    case approved
    case denied

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .sent: return "Sent"
        case .approved: return "Approved"
        case .denied: return "Denied"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .sent: return "envelope"
        case .approved: return "checkmark.circle"
        case .denied: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .sent: return .blue
        case .approved: return .green
        case .denied: return .red
        }
    }
}
