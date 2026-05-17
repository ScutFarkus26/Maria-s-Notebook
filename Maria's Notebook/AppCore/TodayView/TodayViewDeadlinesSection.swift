// TodayViewDeadlinesSection.swift
// Surfaces upcoming/overdue Initiative deadlines and overdue todos at the
// top of Today, so a teacher sees what needs attention this week.

import SwiftUI
import CoreData

extension TodayView {

    var deadlinesListSection: some View {
        DeadlinesSectionView()
    }
}

struct DeadlinesSectionView: View {
    @Environment(\.appRouter) private var appRouter

    @AppStorage("Today.deadlineWarningDays") private var warningDays: Int = 7

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDInitiative.deadline, ascending: true)],
        predicate: NSPredicate(format: "completedAt == nil AND deadline != nil")
    ) private var initiativesRaw: FetchedResults<CDInitiative>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItemEntity.dueDate, ascending: true)],
        predicate: NSPredicate(format: "isCompleted == NO AND dueDate != nil")
    ) private var todosRaw: FetchedResults<CDTodoItemEntity>

    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    private var windowEnd: Date {
        Calendar.current.date(byAdding: .day, value: warningDays, to: startOfToday) ?? startOfToday
    }

    private var overdueInitiatives: [CDInitiative] {
        initiativesRaw.filter { ($0.deadline ?? .distantFuture) < startOfToday }
    }

    private var todayInitiatives: [CDInitiative] {
        initiativesRaw.filter {
            guard let d = $0.deadline else { return false }
            return Calendar.current.isDateInToday(d)
        }
    }

    private var upcomingInitiatives: [CDInitiative] {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        return initiativesRaw.filter {
            guard let d = $0.deadline else { return false }
            return d >= endOfToday && d <= windowEnd
        }
    }

    private var overdueTodos: [CDTodoItemEntity] {
        todosRaw.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
    }

    private var hasContent: Bool {
        !overdueInitiatives.isEmpty || !todayInitiatives.isEmpty ||
        !upcomingInitiatives.isEmpty || !overdueTodos.isEmpty
    }

    var body: some View {
        if hasContent {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(overdueInitiatives, id: \.objectID) { initiative in
                        initiativeRow(initiative, urgency: .overdue)
                    }
                    ForEach(todayInitiatives, id: \.objectID) { initiative in
                        initiativeRow(initiative, urgency: .today)
                    }
                    ForEach(upcomingInitiatives, id: \.objectID) { initiative in
                        initiativeRow(initiative, urgency: .upcoming)
                    }
                    if !overdueTodos.isEmpty {
                        overdueTodosRow
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            } header: {
                HStack {
                    sectionHeader("Coming Up")
                    Spacer()
                    Text("\(warningDays)d window")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private enum Urgency {
        case overdue, today, upcoming
        var color: Color {
            switch self {
            case .overdue: return .red
            case .today: return .orange
            case .upcoming: return .secondary
            }
        }
    }

    @ViewBuilder
    private func initiativeRow(_ initiative: CDInitiative, urgency: Urgency) -> some View {
        Button {
            appRouter.pendingInitiativeID = initiative.id?.uuidString
            appRouter.navigateTo(.planningInitiatives)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: initiative.symbol ?? InitiativeSymbol.defaultValue.rawValue)
                    .foregroundStyle(InitiativeColor.from(raw: initiative.colorRaw).swiftUIColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(initiative.title.isEmpty ? "Untitled" : initiative.title)
                        .foregroundStyle(.primary)
                    if let deadline = initiative.deadline {
                        Text(deadlineLabel(deadline, urgency: urgency))
                            .font(.caption2)
                            .foregroundStyle(urgency.color)
                    }
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

    private func deadlineLabel(_ deadline: Date, urgency: Urgency) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: startOfToday, to: cal.startOfDay(for: deadline)).day ?? 0
        switch urgency {
        case .overdue:
            return "\(-days) day\(days == -1 ? "" : "s") overdue"
        case .today:
            return "Due today"
        case .upcoming:
            if days == 1 { return "Due tomorrow" }
            return "Due in \(days) days"
        }
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
