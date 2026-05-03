// TodayViewDayCardsSection.swift
// Day-aware top cards — small dismissable banners that surface only when relevant:
// Friday Review on Fridays, Prep Checklist when items remain in the morning,
// Needs Lesson when students are overdue. Dismissals are per-date.

import SwiftUI
import CoreData

extension TodayView {

    enum DayCard: String, CaseIterable {
        case fridayReview
        case prepChecklist
        case needsLesson

        var title: String {
            switch self {
            case .fridayReview: return "Friday Review"
            case .prepChecklist: return "Prep Checklist"
            case .needsLesson: return "Needs Lesson"
            }
        }

        var icon: String {
            switch self {
            case .fridayReview: return "checkmark.seal"
            case .prepChecklist: return "checklist.checked"
            case .needsLesson: return "clock.badge.exclamationmark"
            }
        }

        var tint: Color {
            switch self {
            case .fridayReview: return .green
            case .prepChecklist: return .blue
            case .needsLesson: return .orange
            }
        }

        var navItem: RootView.NavigationItem {
            switch self {
            case .fridayReview: return .fridayReview
            case .prepChecklist: return .prepChecklist
            case .needsLesson: return .needsLesson
            }
        }
    }

    var dayCardsListSection: some View {
        // Reading dayCardsRefreshTrigger here makes the section re-evaluate after a dismiss.
        _ = dayCardsRefreshTrigger
        return Section {
            let cards = activeDayCards
            if !cards.isEmpty {
                ForEach(cards, id: \.0) { card, subtitle in
                    dayCardRow(card: card, subtitle: subtitle)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
        } header: {
            if !activeDayCards.isEmpty {
                sectionHeader("For Today")
            }
        }
    }

    /// Cards visible right now: condition met AND not dismissed for the selected date.
    var activeDayCards: [(DayCard, String)] {
        DayCard.allCases.compactMap { card in
            guard !isCardDismissed(card) else { return nil }
            guard let subtitle = subtitleIfActive(card) else { return nil }
            return (card, subtitle)
        }
    }

    @ViewBuilder
    private func dayCardRow(card: DayCard, subtitle: String) -> some View {
        Button {
            appRouter.selectedNavItem = card.navItem
        } label: {
            HStack(spacing: 12) {
                Image(systemName: card.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(card.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismissCard(card)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss \(card.title) for today")
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conditions

    private func subtitleIfActive(_ card: DayCard) -> String? {
        switch card {
        case .fridayReview:
            let weekday = Calendar.current.component(.weekday, from: viewModel.date)
            // Sunday = 1, Friday = 6
            guard weekday == 6 else { return nil }
            return "Wrap up the week"
        case .prepChecklist:
            // Show only on the actual current day, not on past/future browsing
            guard Calendar.current.isDateInToday(viewModel.date) else { return nil }
            let hour = Calendar.current.component(.hour, from: Date())
            guard hour < 12 else { return nil }
            let remaining = prepChecklistRemainingCount
            guard remaining > 0 else { return nil }
            return "\(remaining) item\(remaining == 1 ? "" : "s") remaining"
        case .needsLesson:
            let count = needsLessonCount
            guard count > 0 else { return nil }
            return "\(count) student\(count == 1 ? "" : "s") overdue for a lesson"
        }
    }

    // MARK: - Dismissal

    private func cardDismissalKey(_ card: DayCard) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        let dayString = formatter.string(from: viewModel.date)
        return "\(UserDefaultsKeys.todayDayCardDismissedPrefix)\(dayString).\(card.rawValue)"
    }

    private func isCardDismissed(_ card: DayCard) -> Bool {
        UserDefaults.standard.bool(forKey: cardDismissalKey(card))
    }

    private func dismissCard(_ card: DayCard) {
        adaptiveWithAnimation(.snappy(duration: 0.2)) {
            UserDefaults.standard.set(true, forKey: cardDismissalKey(card))
            dayCardsRefreshTrigger &+= 1
        }
    }
}
