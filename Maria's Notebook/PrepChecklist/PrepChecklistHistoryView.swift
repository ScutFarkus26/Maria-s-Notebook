// PrepChecklistHistoryView.swift
// Calendar-style history view showing daily completion status and streaks.

import SwiftUI
import CoreData

struct PrepChecklistHistoryView: View {
    let checklist: CDPrepChecklist
    @Environment(\.managedObjectContext) private var viewContext

    @State private var completionHistory: [Date: Double] = [:]
    @State private var currentStreak: Int = 0
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private let daysToShow = 28 // 4 weeks

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Streak header
                streakHeader

                // Calendar grid
                calendarGrid

                // Legend
                legend
            }
            .padding()
        }
        .onAppear { loadHistory() }
    }

    // MARK: - Streak Header

    private var streakHeader: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(currentStreak)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                Text("Current Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                let completeDays = completionHistory.filter { $0.value >= 1.0 }.count
                Text("\(completeDays)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.success)
                Text("Complete Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                let partialDays = completionHistory.filter { $0.value > 0 && $0.value < 1.0 }.count
                Text("\(partialDays)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.warning)
                Text("Partial Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(daysToShow - 1), to: today)!

        return VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            let days = (0..<daysToShow).map { offset in
                calendar.date(byAdding: .day, value: offset, to: startDate)!
            }

            // Pad to start on Monday
            let firstWeekday = calendar.component(.weekday, from: startDate)
            let mondayOffset = (firstWeekday + 5) % 7 // Convert to Monday=0
            let paddedDays: [Date?] = Array(repeating: nil, count: mondayOffset) + days.map { Optional($0) }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(paddedDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date: date, isToday: calendar.isDate(date, inSameDayAs: today))
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func dayCell(date: Date, isToday: Bool) -> some View {
        let day = calendar.startOfDay(for: date)
        let percentage = completionHistory[day] ?? 0

        let fillColor: Color = {
            if percentage >= 1.0 { return AppColors.success }
            if percentage > 0 { return AppColors.warning }
            return Color.secondary.opacity(UIConstants.OpacityConstants.light)
        }()

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption2)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .primary : .secondary)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fillColor)
                .frame(height: 16)
                .overlay {
                    if percentage >= 1.0 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
        }
        .frame(height: 36)
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: AppColors.success, label: "Complete")
            legendItem(color: AppColors.warning, label: "Partial")
            legendItem(color: .secondary.opacity(UIConstants.OpacityConstants.light), label: "None")
        }
        .font(.caption2)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load History

    private func loadHistory() {
        let items = checklist.itemsArray
        guard !items.isEmpty else { return }

        let itemIDs = items.compactMap { $0.id?.uuidString }
        let itemCount = items.count

        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(daysToShow - 1), to: today)!

        let request = CDFetchRequest(CDPrepChecklistCompletion.self)
        request.predicate = NSPredicate(
            format: "checklistItemID IN %@ AND date >= %@",
            itemIDs, startDate as NSDate
        )

        let completions = viewContext.safeFetch(request)

        // Group by day
        var byDay: [Date: Int] = [:]
        for completion in completions {
            guard let date = completion.date else { continue }
            let day = calendar.startOfDay(for: date)
            byDay[day, default: 0] += 1
        }

        // Convert to percentages
        var history: [Date: Double] = [:]
        for (day, count) in byDay {
            history[day] = min(1.0, Double(count) / Double(itemCount))
        }

        completionHistory = history
        currentStreak = PrepChecklistService.calculateStreak(for: checklist, in: viewContext)
    }
}
