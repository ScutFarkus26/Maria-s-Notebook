// PaginatedList.swift
// Reusable pagination utilities for list views.
// Provides both a state manager and view components for implementing infinite scroll.

import SwiftUI

// MARK: - Pagination State Manager

/// Observable state manager for list pagination.
/// Use this in views that need to display large datasets with "load more" functionality.
@Observable
@MainActor
final class PaginationState {
    /// Current number of items being displayed
    private(set) var displayedCount: Int

    /// Number of items to load per page
    let pageSize: Int

    /// Total count of items (set externally when data changes)
    var totalCount: Int = 0

    /// Whether there are more items to load
    var hasMore: Bool {
        displayedCount < totalCount
    }

    /// Progress indicator (0.0 to 1.0)
    var progress: Double {
        guard totalCount > 0 else { return 1.0 }
        return Double(displayedCount) / Double(totalCount)
    }

    /// Initialize with a page size
    /// - Parameter pageSize: Number of items per page (default: 30)
    init(pageSize: Int = 30) {
        self.pageSize = pageSize
        self.displayedCount = pageSize
    }

    /// Load the next page of items
    func loadMore() {
        guard hasMore else { return }
        let newCount = min(displayedCount + pageSize, totalCount)
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            displayedCount = newCount
        }
    }

    /// Reset pagination to the first page
    func reset() {
        displayedCount = pageSize
    }

    /// Update total count and reset if needed
    /// - Parameter count: New total count
    /// - Parameter resetIfChanged: Whether to reset pagination if count changed significantly
    func updateTotal(_ count: Int, resetIfChanged: Bool = false) {
        let previousTotal = totalCount
        totalCount = count

        // Reset if total decreased significantly or if requested
        if resetIfChanged && abs(count - previousTotal) > pageSize {
            reset()
        }

        // Ensure displayedCount doesn't exceed total
        if displayedCount > totalCount {
            displayedCount = min(pageSize, totalCount)
        }
    }
}

// MARK: - Load More Button

/// A button that appears at the bottom of a list to load more items.
struct LoadMoreButton: View {
    let remainingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                Text("Load \(min(remainingCount, 30)) more")
                Text("(\(remainingCount) remaining)")
                    .foregroundStyle(.secondary)
            }
            .font(AppTheme.ScaledFont.bodySemibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }
}

// MARK: - Load More Trigger

/// An invisible view that triggers loading more items when it appears on screen.
/// Place this at the end of your list for automatic infinite scroll.
struct LoadMoreTrigger: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                action()
            }
    }
}

// MARK: - Paginated List Footer

/// A footer view showing pagination status and load more button.
struct PaginatedListFooter: View {
    var state: PaginationState
    let itemName: String

    init(state: PaginationState, itemName: String = "items") {
        self.state = state
        self.itemName = itemName
    }

    var body: some View {
        if state.totalCount > 0 {
            VStack(spacing: 8) {
                if state.hasMore {
                    LoadMoreButton(
                        remainingCount: state.totalCount - state.displayedCount,
                        action: { state.loadMore() }
                    )
                }

                Text("Showing \(state.displayedCount) of \(state.totalCount) \(itemName)")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Array Extension for Pagination

extension Array {
    /// Returns a paginated slice of the array.
    /// - Parameter state: The pagination state to use
    /// - Returns: Array containing only the items up to the displayed count
    @MainActor func paginated(using state: PaginationState) -> [Element] {
        Array(prefix(state.displayedCount))
    }
}

// MARK: - Preview

#Preview("Pagination Footer") {
    struct PreviewWrapper: View {
        @State private var state = PaginationState(pageSize: 10)

        var body: some View {
            VStack {
                Text("Total: \(state.totalCount)")
                Text("Displayed: \(state.displayedCount)")
                Text("Has More: \(state.hasMore ? "Yes" : "No")")

                Divider()

                PaginatedListFooter(state: state, itemName: "works")

                Divider()

                Button("Set Total to 50") {
                    state.updateTotal(50)
                }
                Button("Reset") {
                    state.reset()
                }
            }
            .padding()
            .onAppear {
                state.updateTotal(50)
            }
        }
    }

    return PreviewWrapper()
}
