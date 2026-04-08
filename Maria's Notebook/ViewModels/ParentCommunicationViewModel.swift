// ParentCommunicationViewModel.swift
// ViewModel for the Parent Communication hub.

import SwiftUI
import CoreData

@Observable @MainActor
final class ParentCommunicationViewModel {
    private(set) var communications: [CDParentCommunication] = []
    private(set) var students: [CDStudent] = []
    private(set) var isLoading = false

    var selectedTab: CommunicationTab = .drafts
    var searchText: String = ""
    var selectedFilter: CommunicationType?

    // MARK: - Computed

    var drafts: [CDParentCommunication] {
        let filtered = communications.filter { $0.isDraft }
        return applySearch(filtered)
    }

    var sent: [CDParentCommunication] {
        let filtered = communications.filter { !$0.isDraft }
        return applySearch(filtered)
    }

    var sentGroupedByMonth: [(key: String, value: [CDParentCommunication])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: sent) { comm -> String in
            guard let date = comm.sentAt else { return "Unknown" }
            return formatter.string(from: date)
        }

        return grouped.sorted { first, second in
            // Sort by most recent month first
            let firstDate = sent.first(where: { formatter.string(from: $0.sentAt ?? Date()) == first.key })?.sentAt ?? Date.distantPast
            let secondDate = sent.first(where: { formatter.string(from: $0.sentAt ?? Date()) == second.key })?.sentAt ?? Date.distantPast
            return firstDate > secondDate
        }
    }

    // MARK: - Load

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        communications = ParentCommunicationService.fetchCommunications(in: context)

        let studentRequest = CDFetchRequest(CDStudent.self)
        studentRequest.predicate = NSPredicate(
            format: "enrollmentStatusRaw == %@",
            CDStudent.EnrollmentStatus.enrolled.rawValue
        )
        studentRequest.sortDescriptors = CDStudent.sortByName
        students = context.safeFetch(studentRequest)
    }

    // MARK: - Actions

    @discardableResult
    func createDraft(
        student: CDStudent,
        type: CommunicationType,
        templateBody: String = "",
        subject: String = "",
        context: NSManagedObjectContext
    ) -> CDParentCommunication {
        let expandedBody = ParentCommunicationService.expandTemplate(
            body: templateBody,
            student: student,
            context: context
        )
        let comm = ParentCommunicationService.createDraft(
            studentID: student.id?.uuidString ?? "",
            type: type,
            subject: subject,
            body: expandedBody,
            in: context
        )
        loadData(context: context)
        return comm
    }

    func markAsSent(_ communication: CDParentCommunication, context: NSManagedObjectContext) {
        ParentCommunicationService.markAsSent(communication, context: context)
        loadData(context: context)
    }

    func deleteCommunication(_ communication: CDParentCommunication, context: NSManagedObjectContext) {
        ParentCommunicationService.deleteCommunication(communication, context: context)
        loadData(context: context)
    }

    func studentName(for communication: CDParentCommunication) -> String {
        if let student = students.first(where: { $0.id?.uuidString == communication.studentID }) {
            return StudentFormatter.displayName(for: student)
        }
        return "Unknown Student"
    }

    // MARK: - Private

    private func applySearch(_ items: [CDParentCommunication]) -> [CDParentCommunication] {
        var result = items

        if let filter = selectedFilter {
            result = result.filter { $0.communicationType == filter }
        }

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.subject.lowercased().contains(search) ||
                $0.body.lowercased().contains(search) ||
                $0.templateName.lowercased().contains(search) ||
                studentName(for: $0).lowercased().contains(search)
            }
        }

        return result
    }
}
