// GoingOutViewModel.swift
// ViewModel for Going-Out list and management.

import Foundation
import CoreData
import SwiftUI

@Observable
@MainActor
final class GoingOutViewModel {
    // MARK: - Outputs

    private(set) var goingOuts: [CDGoingOut] = []
    private(set) var isLoading = false

    // MARK: - Inputs

    var statusFilter: GoingOutStatus?
    var searchText: String = ""

    // MARK: - Computed

    var filteredGoingOuts: [CDGoingOut] {
        var result = goingOuts

        // Status filter
        if let filter = statusFilter {
            result = result.filter { $0.status == filter }
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.destination.lowercased().contains(query) ||
                $0.purpose.lowercased().contains(query)
            }
        }

        return result
    }

    var activeGoingOuts: [CDGoingOut] {
        filteredGoingOuts.filter { $0.status != .completed && $0.status != .cancelled }
    }

    var completedGoingOuts: [CDGoingOut] {
        filteredGoingOuts.filter { $0.status == .completed }
    }

    // MARK: - Load

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let request = CDFetchRequest(CDGoingOut.self)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDGoingOut.createdAt, ascending: false)]
        goingOuts = context.safeFetch(request)
    }

    // MARK: - CRUD

    @discardableResult
    func createGoingOut(
        context: NSManagedObjectContext,
        title: String,
        purpose: String = "",
        destination: String = "",
        proposedDate: Date? = nil,
        studentIDs: [UUID] = []
    ) -> CDGoingOut {
        let goingOut = CDGoingOut(context: context)
        goingOut.id = UUID()
        goingOut.title = title
        goingOut.purpose = purpose
        goingOut.destination = destination
        goingOut.proposedDate = proposedDate
        goingOut.studentIDsArray = studentIDs.map(\.uuidString)
        goingOut.createdAt = Date()
        context.safeSave()
        loadData(context: context)
        return goingOut
    }

    func updateStatus(_ goingOut: CDGoingOut, to newStatus: GoingOutStatus, context: NSManagedObjectContext) {
        goingOut.status = newStatus
        if newStatus == .completed {
            goingOut.actualDate = Date()
        }
        context.safeSave()
    }

    func delete(_ goingOut: CDGoingOut, context: NSManagedObjectContext) {
        context.delete(goingOut)
        context.safeSave()
        loadData(context: context)
    }
}
