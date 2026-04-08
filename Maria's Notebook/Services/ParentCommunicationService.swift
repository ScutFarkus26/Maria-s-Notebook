// ParentCommunicationService.swift
// Service for parent communication CRUD and template expansion.

import Foundation
import CoreData

enum ParentCommunicationService {

    // MARK: - Fetch

    @MainActor
    static func fetchCommunications(
        in context: NSManagedObjectContext,
        studentID: String? = nil
    ) -> [CDParentCommunication] {
        let request = CDFetchRequest(CDParentCommunication.self)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        if let studentID {
            request.predicate = NSPredicate(format: "studentID == %@", studentID)
        }

        return context.safeFetch(request)
    }

    @MainActor
    static func fetchDrafts(in context: NSManagedObjectContext) -> [CDParentCommunication] {
        let request = CDFetchRequest(CDParentCommunication.self)
        request.predicate = NSPredicate(format: "sentAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        return context.safeFetch(request)
    }

    @MainActor
    static func fetchSent(in context: NSManagedObjectContext) -> [CDParentCommunication] {
        let request = CDFetchRequest(CDParentCommunication.self)
        request.predicate = NSPredicate(format: "sentAt != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "sentAt", ascending: false)]
        return context.safeFetch(request)
    }

    // MARK: - Create

    @MainActor
    @discardableResult
    static func createDraft(
        studentID: String,
        type: CommunicationType,
        templateName: String = "",
        subject: String = "",
        body: String = "",
        in context: NSManagedObjectContext
    ) -> CDParentCommunication {
        let comm = CDParentCommunication(context: context)
        comm.studentID = studentID
        comm.communicationType = type
        comm.templateName = templateName
        comm.subject = subject
        comm.body = body
        context.safeSave()
        return comm
    }

    // MARK: - Actions

    @MainActor
    static func markAsSent(_ communication: CDParentCommunication, context: NSManagedObjectContext) {
        communication.sentAt = Date()
        communication.modifiedAt = Date()
        context.safeSave()
    }

    @MainActor
    static func deleteCommunication(_ communication: CDParentCommunication, context: NSManagedObjectContext) {
        context.delete(communication)
        context.safeSave()
    }

    // MARK: - Template Expansion

    @MainActor
    static func expandTemplate(
        body: String,
        student: CDStudent,
        context: NSManagedObjectContext
    ) -> String {
        var result = body
        result = result.replacingOccurrences(of: "{{studentFirstName}}", with: student.firstName)
        result = result.replacingOccurrences(of: "{{studentLastName}}", with: student.lastName)
        result = result.replacingOccurrences(of: "{{currentDate}}", with: Date().formatted(date: .long, time: .omitted))

        // Level
        result = result.replacingOccurrences(of: "{{studentLevel}}", with: student.level.rawValue)

        return result
    }
}
