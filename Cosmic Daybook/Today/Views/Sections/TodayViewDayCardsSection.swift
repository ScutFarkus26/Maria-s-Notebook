// TodayViewDayCardsSection.swift
// Day-aware top cards — small banners that surface only when relevant:
// "N children need a lesson" when students are overdue, and "Restock: 3 for
// the office run, 2 to order" when something is needed (an assistant marking
// a staple Out shows here, and nowhere else). Each card names its two actions
// (its own, and Hide until tomorrow); hiding is per date. On the Mac
// the card heads the right column; on iPhone and iPad it follows Gone quiet,
// just above the todos, as it does there.

import SwiftUI
import CoreData

extension TodayView {

    enum DayCard: String, CaseIterable {
        case needsLesson
        case restock

        /// What the card is called in accessibility labels; the visible title
        /// carries the count (`DayCardText`).
        var name: String {
            switch self {
            case .needsLesson: return "Needs a lesson"
            case .restock: return "Restock"
            }
        }

        /// The card's primary action (`destination`).
        var actionTitle: String {
            switch self {
            case .needsLesson: return "Plan lessons"
            case .restock: return "Open Restock"
            }
        }

        var icon: String {
            switch self {
            case .needsLesson: return "clock.badge.exclamationmark"
            case .restock: return "shippingbox"
            }
        }

        var tint: Color {
            switch self {
            case .needsLesson: return .orange
            case .restock: return RestockStyle.outFill
            }
        }

        /// Where the card's action goes. The waiting-students list moved into
        /// To Schedule, beside the lessons you would give — so the lesson
        /// banner opens the workspace there.
        var destination: DayCardDestination {
            switch self {
            case .needsLesson: return .lessonsAndWork(.toSchedule)
            case .restock: return .section(.supplies)
            }
        }
    }

    /// Where a day card's action goes.
    enum DayCardDestination: Equatable {
        case lessonsAndWork(TriageBucket)
        case section(RootView.NavigationItem)
    }

    /// A live card's words, computed from today's counts.
    struct DayCardText {
        let title: String
        let subtitle: String
    }

    /// No active card means no section at all — an empty `Section` still draws
    /// its header in a `List`, so the gate wraps the whole thing.
    @ViewBuilder
    var dayCardsListSection: some View {
        // Compute once; reused by both the gate and the rows. Reading
        // `activeDayCards` also reads `dayCardsRefreshTrigger`, which is what
        // makes the section re-evaluate after a dismiss.
        let cards = activeDayCards
        if !cards.isEmpty {
            Section {
                ForEach(cards, id: \.0) { card, text in
                    dayCardRow(card: card, text: text)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            } header: {
                sectionHeader("For Today")
            }
        }
    }

    /// Cards visible right now: condition met AND not dismissed for the selected date.
    var activeDayCards: [(DayCard, DayCardText)] {
        // Reading the trigger here is what makes the section re-evaluate after
        // a dismiss — the dismissal itself is stored in UserDefaults, which
        // SwiftUI does not observe.
        _ = dayCardsRefreshTrigger
        return DayCard.allCases.compactMap { card in
            guard !isCardDismissed(card) else { return nil }
            guard let text = textIfActive(card) else { return nil }
            return (card, text)
        }
    }

    private func dayCardRow(card: DayCard, text: DayCardText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: card.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(card.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.primary)
                    Text(text.subtitle)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Explicit button styles keep each button its own tap target
            // inside a List row on iOS, rather than the whole row.
            HStack(spacing: 8) {
                Button(card.actionTitle) {
                    open(card.destination)
                }
                .buttonStyle(.bordered)
                .tint(card.tint)
                Button("Hide until tomorrow") {
                    dismissCard(card)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hide \(card.name) until tomorrow")
            }
            .controlSize(.small)
            .padding(.leading, 36)
        }
    }

    private func open(_ destination: DayCardDestination) {
        switch destination {
        case .lessonsAndWork(let scope): appRouter.navigateToLessonsAndWork(scope)
        case .section(let item): appRouter.navigateTo(item)
        }
    }

    // MARK: - Conditions

    private func textIfActive(_ card: DayCard) -> DayCardText? {
        switch card {
        case .needsLesson:
            let count = viewModel.needsLessonCount
            guard count > 0 else { return nil }
            // Same threshold as `TodayViewModel.computeNeedsLessonCount`.
            return DayCardText(
                title: count == 1 ? "1 child needs a lesson" : "\(count) children need a lesson",
                subtitle: "No presentation in 7+ school days."
            )
        case .restock:
            let digest = viewModel.restockDigest
            let counts = (officeRun: digest.officeRun.count, toOrder: digest.toOrder.count)
            guard TodaySectionVisibility.showsRestock(officeRun: counts.officeRun, toOrder: counts.toOrder),
                  let title = digest.cardTitle else { return nil }
            return DayCardText(title: title, subtitle: digest.cardSubtitle)
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
