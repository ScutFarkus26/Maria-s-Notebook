// GoingOutViewModel.swift
// ViewModel for Going-Out list and management.

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class GoingOutViewModel {
    // MARK: - Outputs

    private(set) var goingOuts: [GoingOut] = []
    private(set) var isLoading = false

    // MARK: - Inputs

    var statusFilter: GoingOutStatus?
    var searchText: String = ""

    // MARK: - Computed

    var filteredGoingOuts: [GoingOut] {
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

    var activeGoingOuts: [GoingOut] {
        filteredGoingOuts.filter { $0.status != .completed && $0.status != .cancelled }
    }

    var completedGoingOuts: [GoingOut] {
        filteredGoingOuts.filter { $0.status == .completed }
    }

    // MARK: - Load

    func loadData(context: ModelContext) {
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<GoingOut>(
            sortBy: [SortDescriptor(\GoingOut.createdAt, order: .reverse)]
        )
        goingOuts = context.safeFetch(descriptor)
    }

    // MARK: - CRUD

    @discardableResult
    func createGoingOut(
        context: ModelContext,
        title: String,
        purpose: String = "",
        destination: String = "",
        proposedDate: Date? = nil,
        studentIDs: [UUID] = []
    ) -> GoingOut {
        let goingOut = GoingOut(
            title: title,
            purpose: purpose,
            destination: destination,
            proposedDate: proposedDate,
            studentIDs: studentIDs.map(\.uuidString)
        )
        context.insert(goingOut)
        context.safeSave()
        loadData(context: context)
        return goingOut
    }

    func updateStatus(_ goingOut: GoingOut, to newStatus: GoingOutStatus, context: ModelContext) {
        goingOut.status = newStatus
        if newStatus == .completed {
            goingOut.actualDate = Date()
        }
        context.safeSave()
    }

    func delete(_ goingOut: GoingOut, context: ModelContext) {
        context.delete(goingOut)
        context.safeSave()
        loadData(context: context)
    }
}
