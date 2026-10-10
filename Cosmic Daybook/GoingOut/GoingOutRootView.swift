// GoingOutRootView.swift
// Root view for Going-Out (field trip) tracking.
// Shows a list of going-outs with status filters and detail navigation.

import SwiftUI
import CoreData

struct GoingOutRootView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = GoingOutViewModel()
    @State private var showingNewSheet = false
    @State private var selectedGoingOut: CDGoingOut?

    // Change detection
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDGoingOut.createdAt, ascending: false)])
    private var goingOutsForChange: FetchedResults<CDGoingOut>
    /// Moves on an add or delete, and on a status change, so a going-out
    /// marked done or cancelled moves to its list when she comes back.
    private var changeToken: Int {
        var hasher = Hasher()
        for goingOut in goingOutsForChange {
            hasher.combine(goingOut.objectID)
            hasher.combine(goingOut.statusRaw)
        }
        return hasher.finalize()
    }

    var body: some View {
        content
            .navigationTitle("Going Out")
            .searchable(text: $viewModel.searchText, prompt: "Search going-outs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Image(systemName: SFSymbol.Action.plusCircle)
                    }
                }
            }
            .onAppear { viewModel.loadData(context: modelContext) }
            .onChange(of: changeToken) { _, _ in
                viewModel.loadData(context: modelContext)
            }
            .sheet(isPresented: $showingNewSheet) {
                GoingOutEditorSheet { goingOut in
                    viewModel.loadData(context: modelContext)
                    selectedGoingOut = goingOut
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.goingOuts.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status filter pills
                statusFilterRow
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Summary
                summaryRow
                    .padding(.horizontal)

                goingOutSection("Active", items: viewModel.activeGoingOuts, isSecondary: false)
                goingOutSection("Completed", items: viewModel.completedGoingOuts, isSecondary: true)
                goingOutSection("Cancelled", items: viewModel.cancelledGoingOuts, isSecondary: true)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func goingOutSection(_ title: String, items: [CDGoingOut], isSecondary: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSecondary ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    .padding(.horizontal)

                LazyVStack(spacing: 8) {
                    ForEach(items, id: \.objectID) { goingOut in
                        NavigationLink {
                            GoingOutDetailView(goingOut: goingOut)
                        } label: {
                            GoingOutSidebarRow(goingOut: goingOut)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Status Filter

    private var statusFilterRow: some View {
        HStack(spacing: 8) {
            statusFilterCapsule(nil, label: "All")
            ForEach(GoingOutStatus.allCases) { status in
                statusFilterCapsule(status, label: status.displayName)
            }
            Spacer()
        }
    }

    private func statusFilterCapsule(_ status: GoingOutStatus?, label: String) -> some View {
        let isSelected = viewModel.statusFilter == status
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.statusFilter = status
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.filteredGoingOuts.count)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" going-outs")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Going-Outs", systemImage: "figure.walk")
        } description: {
            Text("Student-initiated excursions will appear here. \(PlatformVerb.tap) + to create one.")
        }
    }
}
