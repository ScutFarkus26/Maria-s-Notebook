// TodayViewDayCardsSection.swift
// Day-aware top cards — small dismissable banners that surface only when relevant:
// Needs Lesson when students are overdue. Dismissals are per-date.

import SwiftUI
import CoreData

extension TodayView {

    enum DayCard: String, CaseIterable {
        case needsLesson

        var title: String {
            switch self {
            case .needsLesson: return "Needs Lesson"
            }
        }

        var icon: String {
            switch self {
            case .needsLesson: return "clock.badge.exclamationmark"
            }
        }

        var tint: Color {
            switch self {
            case .needsLesson: return .orange
            }
        }

        var navItem: RootView.NavigationItem {
            switch self {
            case .needsLesson: return .needsLesson
            }
        }
    }

    var dayCardsListSection: some View {
        // Reading dayCardsRefreshTrigger here makes the section re-evaluate after a dismiss.
        _ = dayCardsRefreshTrigger
        // Compute once; reused by both the section content and the header guard.
        let cards = activeDayCards
        return Section {
            if !cards.isEmpty {
                ForEach(cards, id: \.0) { card, subtitle in
                    dayCardRow(card: card, subtitle: subtitle)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
        } header: {
            if !cards.isEmpty {
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
        case .needsLesson:
            let count = needsLessonCount
            guard count > 0 else { return nil }
            return "\(count) student\(count == 1 ? "" : "s") overdue for a lesson"
        }
    }

    // MARK: - Dismissal

    private func cardDismissalKey(_ card: DayCard) -> String {
        // Use the shared static formatter instead of allocating a DateFormatter on
        // every call — DateFormatter creation is one of the most expensive Foundation
        // operations, and this runs per day-card on the app's most-visited screen.
        let dayString = DateFormatters.isoDateLocal.string(from: viewModel.date)
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
