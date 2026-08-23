// ParentCommunicationEntity.swift
// Core Data entity for tracking parent communications (drafts and sent).

import Foundation
import CoreData

@objc(CDParentCommunication)
public class CDParentCommunication: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var studentID: String
    @NSManaged public var templateName: String
    @NSManaged public var subject: String
    @NSManaged public var body: String
    @NSManaged public var communicationTypeRaw: String
    @NSManaged public var sentAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var notes: String
    @NSManaged public var monthKey: String?
    @NSManaged public var statusRaw: String
    @NSManaged public var recipientsSnapshot: String
    @NSManaged public var includedItemRefs: String
    @NSManaged public var aiGenerated: Bool
    @NSManaged public var includeStudentReflection: Bool
    @NSManaged public var attachPDF: Bool

    // MARK: - Computed Properties

    var communicationType: CommunicationType {
        get { CommunicationType(rawValue: communicationTypeRaw) ?? .custom }
        set { communicationTypeRaw = newValue.rawValue }
    }

    var isDraft: Bool { sentAt == nil }

    var studentUUID: UUID? { UUID(uuidString: studentID) }

    /// Review status; `sentAt` remains the authoritative sent marker.
    var status: MonthlyReportStatus {
        get {
            if sentAt != nil { return .sent }
            return MonthlyReportStatus(rawValue: statusRaw) ?? .draft
        }
        set { statusRaw = newValue.rawValue }
    }

    /// Evidence references ("kind:uuid") backing the narrative, stored as a JSON string array.
    var includedRefs: [String] {
        get {
            guard let data = includedItemRefs.data(using: .utf8), !includedItemRefs.isEmpty else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                includedItemRefs = ""
                return
            }
            includedItemRefs = json
        }
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "ParentCommunication", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.studentID = ""
        self.templateName = ""
        self.subject = ""
        self.body = ""
        self.communicationTypeRaw = CommunicationType.custom.rawValue
        self.sentAt = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.notes = ""
        self.monthKey = nil
        self.statusRaw = MonthlyReportStatus.draft.rawValue
        self.recipientsSnapshot = ""
        self.includedItemRefs = ""
        self.aiGenerated = false
        self.includeStudentReflection = false
        self.attachPDF = false
    }

    // MARK: - Fetching

    /// The monthly report row for one student and month, if it exists.
    nonisolated static func monthlyReportRequest(studentID: String, monthKey: String) -> NSFetchRequest<CDParentCommunication> {
        let request = NSFetchRequest<CDParentCommunication>(entityName: "ParentCommunication")
        request.predicate = NSPredicate(
            format: "studentID == %@ AND monthKey == %@ AND communicationTypeRaw == %@",
            studentID, monthKey, CommunicationType.monthlyReport.rawValue
        )
        request.fetchLimit = 1
        return request
    }
}

/// Lifecycle of a monthly parent report draft.
enum MonthlyReportStatus: String, CaseIterable, Sendable {
    case draft
    case reviewed
    case sent

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .reviewed: return "Reviewed"
        case .sent: return "Sent"
        }
    }
}
