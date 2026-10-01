// WaitingStudentsRail.swift
// The column of children who have waited longest, beside the lessons you could
// give them.
//
// It sits next to the ready presentations rather than replacing them, because
// the guide's question is three things at once: who has waited, what could they
// have, and which day does it go on. Tapping a name narrows the lessons beside
// it; the calendar is pinned below. Left, then center, then down.
//
// Replaces two earlier lists that answered the same question in two places and
// disagreed about who belonged on it.
//
// The chrome is `WaitingStudentsColumn`, shared with the Work half's
// `QuietStudentsRail`. Only what is genuinely about lessons stays here: which
// children the scope hides, and what tapping one does to the cards beside it.
//
// The lessons vocabulary draws this column grouped, one line per child
// (`WaitingStudentBands`), so the scope control here is a small menu in the
// header rather than a segmented control on a band of its own.

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
            isSearching: !filterState.debouncedSearchText.trimmed().isEmpty,
            onSelect: select
        ) {
            scopeMenu
        } emptyState: {
            emptyStateMessage
        }
    }

    /// Everyone or Unscheduled, as an icon in the header. The icon fills and
    /// takes the accent color while it is narrowing the list, the way a
    /// filter control does elsewhere on the platform, so a shorter list is
    /// never a mystery.
    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: scopeBinding) {
                ForEach(WaitingStudentsScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: scope == .everyone
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(scope == .everyone ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .help(scope == .everyone
            ? "Showing everyone. Choose Unscheduled for only children with no lesson on the calendar."
            : "Showing only children with no lesson on the calendar")
        .accessibilityLabel("Show")
        .accessibilityValue(scope.title)
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
                filterState.selectedChip = .ready
            }
        }
    }
}
