// TodayViewSectionOrder.swift
// The order Today's sections appear in, on each platform.
//
// The sequence is the guide's morning, read top to bottom: what is in front of
// her now (Right Now, the day's banners, the day's plan, her todo list), then
// what she is watching (ready-for-next, following presentations, recent
// observations), then the external feeds she does not own (calendar,
// reminders), then the monthly nudge, the pad, and last the retrospective of
// what is already done.
//
// Every section below gates itself — see `TodaySectionVisibility` — so this
// file only decides sequence, never whether something shows. The declared
// ordering lives in `TodaySectionVisibility.phoneOrder` /
// `.macLeftColumnOrder` / `.macRightColumnOrder`, which the tests pin; the
// `@ViewBuilder` lists here must match them.

import SwiftUI
import TipKit

extension TodayView {

    var listContent: some View {
        #if os(macOS)
        twoColumnLayout
        #else
        List {
            TipView(pullToRefreshTip)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            phoneSections
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.reload()
            reloadDerivedCounts(force: true)
            pullToRefreshTip.invalidate(reason: .actionPerformed)
        }
        #endif
    }

    #if os(iOS)
    /// Mirrors `TodaySectionVisibility.phoneOrder`.
    @ViewBuilder
    private var phoneSections: some View {
        rightNowListSection
        dayCardsListSection
        agendaListSection
        todosListSection
        watchingListSection
        readyForNextListSection
        followingPresentationsListSection
        recentNotesListSection
        calendarEventsListSection
        remindersListSection
        parentReportsListSection
        dayPadListSection
        doneTodayListSection
    }
    #endif

    #if os(macOS)
    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: glanceable surfaces; Right column: the live agenda.
            List {
                macLeftColumnSections
            }
            .listStyle(.inset)
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            Divider()

            rightColumnContent
        }
    }

    /// Mirrors `TodaySectionVisibility.macLeftColumnOrder` — the phone order
    /// with the agenda lifted out into the right column.
    @ViewBuilder
    private var macLeftColumnSections: some View {
        rightNowListSection
        dayCardsListSection
        todosListSection
        watchingListSection
        readyForNextListSection
        followingPresentationsListSection
        recentNotesListSection
        calendarEventsListSection
        remindersListSection
        parentReportsListSection
        dayPadListSection
        doneTodayListSection
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        if let selectedTodoItem {
            VStack(spacing: 0) {
                HStack {
                    Text("Edit Todo")
                        .font(AppTheme.ScaledFont.body.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        self.selectedTodoItem = nil
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                EditTodoForm(todo: selectedTodoItem)
            }
        } else {
            // Mirrors `TodaySectionVisibility.macRightColumnOrder`.
            List {
                agendaListSection
            }
            .listStyle(.inset)
        }
    }
    #endif
}

// MARK: - Overdue
//
// `deadlinesListSection` / `DeadlinesSectionView` is deliberately absent from
// both orderings. It duplicated the Todos section's own "Overdue" subgroup
// with a single row whose only action was to navigate away from Today, so it
// cost a section header and gave the guide nothing she could not already see
// and act on one section higher up. The view is kept, not placed.
