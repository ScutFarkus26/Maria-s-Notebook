// PrepChecklistDetailView.swift
// Detail view for a single checklist showing items grouped by category with checkboxes.

import SwiftUI
import CoreData

struct PrepChecklistDetailView: View {
    let checklist: CDPrepChecklist
    @Bindable var viewModel: PrepChecklistViewModel
    @Environment(\.managedObjectContext) private var viewContext

    @State private var showingAddItem = false
    @State private var showingResetConfirmation = false
    @State private var showingHistory = false
    @State private var showingEditor = false

    var body: some View {
        let items = checklist.itemsArray
        let grouped = Dictionary(grouping: items) { $0.category.isEmpty ? "General" : $0.category }
        let sortedCategories = grouped.keys.sorted()
        let percentage = viewModel.completionPercentage(for: checklist)

        ScrollView {
            VStack(spacing: 16) {
                // Progress header
                progressHeader(percentage: percentage, items: items)

                // Grouped items
                ForEach(sortedCategories, id: \.self) { category in
                    categorySection(category, items: grouped[category] ?? [])
                }

                // Add item button
                Button {
                    showingAddItem = true
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(checklist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Checklist", systemImage: "pencil")
                    }

                    Button {
                        showingHistory = true
                    } label: {
                        Label("History", systemImage: "calendar")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Today", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            NavigationStack {
                PrepChecklistItemEditorSheet(checklist: checklist, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                PrepChecklistEditorSheet(viewModel: viewModel, checklist: checklist)
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                PrepChecklistHistoryView(checklist: checklist)
                    .navigationTitle("History")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingHistory = false }
                        }
                    }
            }
        }
        .alert("Reset Today's Progress", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                viewModel.resetChecklist(checklist, context: viewContext)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will uncheck all items for today. History for previous days is preserved.")
        }
    }

    // MARK: - Progress Header

    private func progressHeader(percentage: Double, items: [CDPrepChecklistItem]) -> some View {
        let completed = viewModel.completedCount(for: checklist)
        let total = items.count
        let streak = viewModel.streak(for: checklist)

        return VStack(spacing: 10) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(checklist.color.opacity(UIConstants.OpacityConstants.light))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(checklist.color.gradient)
                        .frame(width: max(0, geo.size.width * percentage))
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(completed) of \(total) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("\(streak) day streak")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                }

                Text("\(Int(percentage * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(percentage >= 1.0 ? AppColors.success : checklist.color)
            }
        }
        .cardStyle()
    }

    // MARK: - Category Section

    private func categorySection(_ category: String, items: [CDPrepChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(items, id: \.id) { item in
                itemRow(item)
            }
        }
        .cardStyle()
    }

    private func itemRow(_ item: CDPrepChecklistItem) -> some View {
        let isCompleted = viewModel.isItemCompleted(item)

        return HStack(spacing: 10) {
            Button {
                viewModel.toggleItem(item, context: viewContext)
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? AppColors.success : .secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.subheadline)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)

            Spacer()

            if isCompleted, let completedAt = viewModel.todayCompletions[item.id?.uuidString ?? ""] {
                Text(completedAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleItem(item, context: viewContext)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteItem(item, context: viewContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
