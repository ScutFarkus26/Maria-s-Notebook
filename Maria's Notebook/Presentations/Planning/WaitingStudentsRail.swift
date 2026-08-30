// WaitingStudentsRail.swift
// The column of children who have waited longest, beside the lessons you could
// give them.
//
// It sits next to the ready presentations rather than replacing them, because
// the guide's question is three things at once: who has waited, what could they
// have, and which day does it go on. Tapping a name narrows the lessons beside
// it; the calendar is pinned below. Left, then centre, then down.
//
// Replaces two earlier lists that answered the same question in two places and
// disagreed about who belonged on it.
//
// The chrome is `WaitingStudentsColumn`, shared with the Work half's
// `QuietStudentsRail`. Only what is genuinely about lessons stays here: which
// children the scope hides, and what tapping one does to the cards beside it.

import SwiftUI

struct WaitingStudentsRail: View {
    let viewModel: PresentationsViewModel
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    /// Children with a lesson on the calendar from today onward, computed once
    /// per refresh by the workspace rather than re-derived per row.
    let studentIDsWithUpcomingLessons: Set<UUID>

    @SceneStorage("Presentations.waitingScope")
    private var scopeRaw: String = WaitingStudentsScope.everyone.rawValue

    private var scope: WaitingStudentsScope {
        WaitingStudentsScope.resolved(rawValue: scopeRaw)
    }

    private var scopeBinding: Binding<WaitingStudentsScope> {
        Binding(
            get: { scope },
            set: { newValue in
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { scopeRaw = newValue.rawValue }
            }
        )
    }

    private var entries: [WaitingStudent] {
        WaitingStudentsOrder.ordered(
            students: viewModel.cachedStudents,
            daysSince: viewModel.daysSinceLastLessonByStudent,
            studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons,
            scope: scope,
            search: filterState.debouncedSearchText
        )
    }

    var body: some View {
        WaitingStudentsColumn(
            vocabulary: .lessons,
            entries: entries,
            selectedStudentID: coordinator.selectedStudentFilter,
            onSelect: select
        ) {
            Picker("Show", selection: scopeBinding) {
                ForEach(WaitingStudentsScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Everyone, or only children with no lesson on the calendar")
        } emptyState: {
            emptyStateMessage
        }
    }

    @ViewBuilder
    private var emptyStateMessage: some View {
        if !filterState.debouncedSearchText.trimmed().isEmpty {
            ContentUnavailableView.search(text: filterState.debouncedSearchText)
        } else if scope == .unscheduled {
            ContentUnavailableView(
                "Everyone Is Booked",
                systemImage: "calendar.badge.checkmark",
                description: Text("Every child has a lesson coming up.")
            )
        } else {
            ContentUnavailableView(
                "No Children Yet",
                systemImage: "person.2",
                description: Text("Enrolled children appear here, longest wait first.")
            )
        }
    }

    /// Tapping a child narrows the lessons beside the rail to that child, and
    /// tapping them again clears it. The chip in the Ready header is the other
    /// way out, so the filter can never become a state you cannot see or escape.
    private func select(_ student: CDStudent) {
        guard let id = student.id else { return }
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            if coordinator.selectedStudentFilter == id {
                coordinator.clearStudentFilter()
            } else {
                coordinator.filterByStudent(id)
                // A stale chip could otherwise hide every lesson this child has.
                filterState.selectedChip = .all
            }
        }
    }
}
