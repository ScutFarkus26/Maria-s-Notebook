// TransitionPlanDetailView.swift
// Detail view for a single transition plan with checklist and notes.

import SwiftUI
import SwiftData

struct TransitionPlanDetailView: View {
    @Bindable var plan: TransitionPlan
    let viewModel: TransitionPlannerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingNoteEditor = false

    private var sortedItems: [TransitionChecklistItem] {
        (plan.checklistItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var itemsByCategory: [(category: ChecklistCategory, items: [TransitionChecklistItem])] {
        let grouped = Dictionary(grouping: sortedItems, by: \.category)
        return ChecklistCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Student header
                studentHeader
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Status & progress
                statusSection
                    .padding(.horizontal)

                // Checklist
                ForEach(itemsByCategory, id: \.category) { group in
                    checklistSection(category: group.category, items: group.items)
                        .padding(.horizontal)
                }

                // Observation notes
                observationNotesSection
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Transition Plan")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NavigationStack {
                UnifiedNoteEditor(
                    context: .transitionPlan(plan),
                    initialNote: nil,
                    onSave: { _ in showingNoteEditor = false },
                    onCancel: { showingNoteEditor = false }
                )
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    // MARK: - Student Header

    private var studentHeader: some View {
        HStack(spacing: 12) {
            if let student = viewModel.student(for: plan) {
                Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(plan.fromLevelRaw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(plan.toLevelRaw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Progress ring
            HStack(spacing: 12) {
                let pct = viewModel.readinessPercentage(for: plan)
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(
                            pct >= 1.0 ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(pct * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Readiness")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(viewModel.completedCount(for: plan)) of \(viewModel.totalCount(for: plan)) items complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Status progression
            HStack(spacing: 8) {
                ForEach(TransitionStatus.allCases) { status in
                    Button {
                        viewModel.updateStatus(plan, to: status, context: modelContext)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: status.icon)
                                .font(.caption2)
                            Text(status.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(plan.status == status ? .white : status.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(plan.status == status ? status.color : status.color.opacity(UIConstants.OpacityConstants.light))
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .cardStyle()
    }

    // MARK: - Checklist Section

    private func checklistSection(category: ChecklistCategory, items: [TransitionChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(category.color)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                let completed = items.filter(\.isCompleted).count
                Text("\(completed)/\(items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(items) { item in
                Button {
                    viewModel.toggleChecklistItem(item, context: modelContext)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(item.isCompleted ? category.color : Color.secondary.opacity(UIConstants.OpacityConstants.muted))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .strikethrough(item.isCompleted)

                            if let completedAt = item.completedAt {
                                Text("Completed \(completedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - Observation Notes

    private var observationNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Observation Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                        Text("Add Note")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            let linkedNotes = plan.observationNotes ?? []
            if linkedNotes.isEmpty {
                Text("No observation notes yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(linkedNotes.sorted { $0.createdAt > $1.createdAt }) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
                    )
                }
            }
        }
        .cardStyle()
    }
}
