import SwiftUI
import Charts

struct TodoAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    let todos: [TodoItem]
    
    private var completedTodos: [TodoItem] {
        todos.filter(\.isCompleted)
    }
    
    private var completionRate: Double {
        guard !todos.isEmpty else { return 0 }
        return Double(completedTodos.count) / Double(todos.count) * 100
    }
    
    private var completedLast7Days: [TodoItem] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return completedTodos.filter { todo in
            guard let completedAt = todo.completedAt else { return false }
            return completedAt >= sevenDaysAgo
        }
    }
    
    private var completedLast30Days: [TodoItem] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return completedTodos.filter { todo in
            guard let completedAt = todo.completedAt else { return false }
            return completedAt >= thirtyDaysAgo
        }
    }
    
    private var tagBreakdown: [(tag: String, count: Int)] {
        var tagCounts: [String: Int] = [:]
        for todo in completedTodos {
            for tag in todo.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private var priorityBreakdown: [(priority: TodoPriority, count: Int)] {
        let grouped = Dictionary(grouping: completedTodos) { $0.priority }
        return grouped.map { (priority: $0.key, count: $0.value.count) }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }
    
    private var dailyCompletionData: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let last7Days = (0..<7).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))
        }.reversed()
        
        return last7Days.map { date in
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let count = completedTodos.filter { todo in
                guard let completedAt = todo.completedAt else { return false }
                return completedAt >= date && completedAt < nextDay
            }.count
            return (date: date, count: count)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Summary Cards
                    HStack(spacing: 12) {
                        TodoStatCard(
                            title: "Completion Rate",
                            value: String(format: "%.0f%%", completionRate),
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        TodoStatCard(
                            title: "This Week",
                            value: "\(completedLast7Days.count)",
                            icon: "calendar",
                            color: .blue
                        )
                        
                        TodoStatCard(
                            title: "This Month",
                            value: "\(completedLast30Days.count)",
                            icon: "calendar.badge.clock",
                            color: .purple
                        )
                    }
                    
                    // Daily Completion Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Completions (Last 7 Days)")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                        
                        Chart(dailyCompletionData, id: \.date) { item in
                            BarMark(
                                x: .value("Day", item.date, unit: .day),
                                y: .value("Completed", item.count)
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                        .frame(height: 200)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow))
                            }
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
                    .cornerRadius(12)
                    
                    // Tag Breakdown
                    if !tagBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completions by Tag")
                                .font(AppTheme.ScaledFont.calloutSemibold)
                            
                            ForEach(tagBreakdown, id: \.tag) { item in
                                HStack {
                                    TagBadge(tag: item.tag, compact: true)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(AppTheme.ScaledFont.bodySemibold)
                                        .foregroundStyle(TodoTagHelper.tagColor(item.tag).color)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding()
                        .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
                        .cornerRadius(12)
                    }
                    
                    // Priority Breakdown
                    if !priorityBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Completions by Priority")
                                .font(AppTheme.ScaledFont.calloutSemibold)
                            
                            ForEach(priorityBreakdown, id: \.priority) { item in
                                HStack {
                                    Image(systemName: item.priority.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(item.priority.color))
                                    Text(item.priority.rawValue)
                                        .font(AppTheme.ScaledFont.body)
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(AppTheme.ScaledFont.bodySemibold)
                                        .foregroundStyle(Color(item.priority.color))
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .padding()
                        .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
                        .cornerRadius(12)
                    }
                    
                    // Insights
                    if let topTag = tagBreakdown.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Insights", systemImage: "lightbulb.fill")
                                .font(AppTheme.ScaledFont.calloutSemibold)
                                .foregroundStyle(AppColors.warning)

                            let tagName = TodoTagHelper.tagName(topTag.tag)
                            Text("You complete the most \(tagName) tasks (\(topTag.count) total)")
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TodoStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppTheme.ScaledFont.captionSmall)
            }
            .foregroundStyle(.secondary)
            
            Text(value)
                .font(AppTheme.ScaledFont.header)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(UIConstants.OpacityConstants.light))
        .cornerRadius(12)
    }
}
