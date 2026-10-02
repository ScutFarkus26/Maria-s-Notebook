// TodayViewSectionOrder.swift
// The order Today's sections appear in, on each platform.
//
// The phone sequence is the guide's morning, read top to bottom: what is in
// front of her now (Right Now, the day's banners, the day's plan, her todo
// list), then what she is watching (ready-for-next, following presentations,
// recent observations), then the external feeds she does not own (calendar,
// reminders), then the monthly nudge, the pad, and last the retrospective of
// what is already done.
//
// The Mac splits that in two. The plan is the wide left column — the lessons,
// then the meetings, then Gone quiet.
// A fixed 340-pt right column holds the rest in the phone's order: the
// Needs-a-lesson card, Todos, then the count-gated sections. Right Now is not
// placed on the Mac (the plan's first row is the next thing to do), and a
// todo opens in an inspector at the trailing edge, below the attendance band,
// instead of replacing either column.
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
            // Sample Class never syncs, and the tip promises an iCloud sync.
            if !isSampleClassroom {
                TipView(pullToRefreshTip)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            phoneSections
        }
        .listStyle(.insetGrouped)
        .quickCaptureButtonClearance()
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
        meetingsListSection
        goneQuietListSection
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
    /// Width of the Mac's right column. Fixed, so the plan takes whatever the
    /// window gives and the side column reads the same at every size.
    private static let macRightColumnWidth: CGFloat = 340

    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            List {
                macLeftColumnSections
            }
            .listStyle(.inset)
            .frame(minWidth: 360, maxWidth: .infinity)

            Divider()

            List {
                macRightColumnSections
            }
            .listStyle(.inset)
            .frame(width: Self.macRightColumnWidth)
        }
        .inspector(isPresented: isTodoInspectorPresented) {
            todoInspectorContent
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }

    /// Mirrors `TodaySectionVisibility.macLeftColumnOrder` — the day's plan:
    /// the lessons, then the meetings, then the work gone quiet.
    @ViewBuilder
    private var macLeftColumnSections: some View {
        agendaListSection
        meetingsListSection
        goneQuietListSection
    }

    /// Mirrors `TodaySectionVisibility.macRightColumnOrder` — the phone order
    /// without the plan and without Right Now.
    @ViewBuilder
    private var macRightColumnSections: some View {
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

    /// Whether the todo inspector is open: exactly when a todo is selected.
    /// Closing it (Done, or the system's own close) clears the selection.
    private var isTodoInspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedTodoItem != nil },
            set: { isPresented in
                if !isPresented { selectedTodoItem = nil }
            }
        )
    }

    /// The todo editor, in the inspector. It used to take over
    /// the agenda column, so opening a todo hid the day's plan.
    @ViewBuilder
    private var todoInspectorContent: some View {
        if let selectedTodoItem {
            VStack(spacing: 0) {
                HStack {
                    Text("Edit Todo")
                        .font(AppTheme.ScaledFont.body.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        self.selectedTodoItem = nil
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // A fresh form per todo: switching rows saves the old one on
                // its way out (`EditTodoForm` saves on disappear).
                EditTodoForm(todo: selectedTodoItem)
                    .id(selectedTodoItem.objectID)
            }
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
