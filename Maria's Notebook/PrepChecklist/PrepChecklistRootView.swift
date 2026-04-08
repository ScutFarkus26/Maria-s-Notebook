// PrepChecklistRootView.swift
// Root view for classroom environment prep checklists with completion progress.

import SwiftUI
import CoreData

struct PrepChecklistRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = PrepChecklistViewModel()
    @State private var showingNewChecklist = false

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDPrepChecklistCompletion.id, ascending: true)]
    ) private var completions: FetchedResults<CDPrepChecklistCompletion>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDPrepChecklist.id, ascending: true)]
    ) private var checklists: FetchedResults<CDPrepChecklist>

    private var changeToken: Int { completions.count + checklists.count }

    var body: some View {
        content
            .navigationTitle("Prep Checklist")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in viewModel.loadData(context: viewContext) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewChecklist = true
                    } label: {
                        Label("New Checklist", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewChecklist) {
                NavigationStack {
                    PrepChecklistEditorSheet(viewModel: viewModel, checklist: nil)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.checklists.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.checklists, id: \.id) { checklist in
                    NavigationLink(value: checklist.id) {
                        checklistCard(checklist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationDestination(for: UUID.self) { checklistID in
            if let checklist = viewModel.checklists.first(where: { $0.id == checklistID }) {
                PrepChecklistDetailView(checklist: checklist, viewModel: viewModel)
            }
        }
    }

    // MARK: - Checklist Card

    private func checklistCard(_ checklist: CDPrepChecklist) -> some View {
        let percentage = viewModel.completionPercentage(for: checklist)
        let completed = viewModel.completedCount(for: checklist)
        let total = checklist.itemsArray.count
        let streak = viewModel.streak(for: checklist)

        return HStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(checklist.color.opacity(UIConstants.OpacityConstants.light), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(checklist.color.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: checklist.icon)
                    .font(.title3)
                    .foregroundStyle(checklist.color)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(checklist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(completed)/\(total) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if streak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text("\(streak)")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.orange)
                    }
                }

                Text(checklist.scheduleType.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Percentage
            Text("\(Int(percentage * 100))%")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(percentage >= 1.0 ? AppColors.success : checklist.color)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .cardStyle()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Checklists", systemImage: "checklist.checked")
        } description: {
            Text("Create a prep checklist to track daily classroom setup tasks.")
        } actions: {
            Button("Create Checklist") {
                showingNewChecklist = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
