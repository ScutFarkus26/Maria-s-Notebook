// GoingOutRootView.swift
// Root view for Going-Out (field trip) tracking.
// Shows a list of going-outs with status filters and detail navigation.

import SwiftUI
import CoreData

struct GoingOutRootView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @State private var viewModel = GoingOutViewModel()
    @State private var showingNewSheet = false
    @State private var selectedGoingOut: GoingOut?

    // Change detection
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDGoingOut.createdAt, ascending: false)])
    private var goingOutsForChange: FetchedResults<CDGoingOut>
    private var changeToken: Int { goingOutsForChange.count }

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

                // Active going-outs
                if !viewModel.activeGoingOuts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.activeGoingOuts, id: \.objectID) { goingOut in
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

                // Completed going-outs
                if !viewModel.completedGoingOuts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completed")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.completedGoingOuts, id: \.objectID) { goingOut in
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
            .padding(.bottom, 24)
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
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
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
            Text("Student-initiated excursions will appear here. Tap + to create one.")
        }
    }
}
