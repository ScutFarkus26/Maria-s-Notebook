// TodayViewSectionOrder.swift
// The order Today's sections appear in, on each platform.
//
// The phone sequence is the guide's morning, read top to bottom: the day's
// plan (the lessons, led by the Next card, then the meetings and the work
// gone quiet), the Needs-a-lesson card and her todo list, then what she is
// watching (ready-for-next, following presentations, recent observations),
// then the external feeds she does not own (calendar, reminders), then the
// monthly nudge, the pad, and last the retrospective of what is already done.
// The iPad draws the same list, under the attendance band.
//
// The Mac splits that in two. The plan is the wide left column — the lessons,
// then the meetings, then Gone quiet.
// A fixed 340-pt right column holds the rest in the phone's order: the
// Needs-a-lesson card, Todos, then the count-gated sections. A todo opens in
// an inspector at the window's trailing edge instead of replacing either
// column.
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
        agendaListSection
        meetingsListSection
        goneQuietListSection
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
    /// without the plan.
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

    /// The todo editor, at the window's trailing edge beside the band and
    /// both columns. Attached to the columns alone, the inspector made the
    /// Mac draw a toolbar-height grey band across the top of both lists,
    /// covering their first rows, even while it was closed.
    func todoInspector(on content: some View) -> some View {
        content.inspector(isPresented: isTodoInspectorPresented) {
            todoInspectorContent
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
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
