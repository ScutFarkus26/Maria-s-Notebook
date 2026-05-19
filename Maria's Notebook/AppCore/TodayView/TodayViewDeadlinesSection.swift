// TodayViewDeadlinesSection.swift
// Surfaces overdue todos at the top of Today, so a teacher sees
// what slipped past its deadline.

import SwiftUI
import CoreData

extension TodayView {

    var deadlinesListSection: some View {
        DeadlinesSectionView()
    }
}

struct DeadlinesSectionView: View {
    @Environment(\.appRouter) private var appRouter

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItemEntity.dueDate, ascending: true)],
        predicate: NSPredicate(format: "isCompleted == NO AND dueDate != nil")
    ) private var todosRaw: FetchedResults<CDTodoItemEntity>

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    private var overdueTodos: [CDTodoItemEntity] {
        todosRaw.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
    }

    var body: some View {
        if !overdueTodos.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    overdueTodosRow
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            } header: {
                sectionHeader("Overdue")
            }
        }
    }

    @ViewBuilder
    private var overdueTodosRow: some View {
        Button {
            appRouter.navigateTo(.todos)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(overdueTodos.count) overdue todo\(overdueTodos.count == 1 ? "" : "s")")
                        .foregroundStyle(.primary)
                    Text("Open the Todos surface to review")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}
