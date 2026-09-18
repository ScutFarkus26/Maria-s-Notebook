// WaitingStudentsStrip.swift
// The waiting list on a phone: one scrolling row of names above the lessons.
//
// The chrome is `WaitingStudentsBar`, shared with the Work half's
// `QuietStudentsStrip`. What stays here is what is about lessons: the scope, the
// wording when nobody is waiting, and what tapping a child does to the cards.

import SwiftUI

struct WaitingStudentsStrip: View {
    let viewModel: PresentationsViewModel
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    let studentIDsWithUpcomingLessons: Set<UUID>

    @SceneStorage("Presentations.waitingScope")
    private var scopeRaw: String = WaitingStudentsScope.everyone.rawValue

    private var scope: WaitingStudentsScope {
        WaitingStudentsScope.resolved(rawValue: scopeRaw)
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
        WaitingStudentsBar(
            vocabulary: .lessons,
            entries: entries,
            selectedStudentID: coordinator.selectedStudentFilter,
            emptyMessage: scope == .unscheduled ? "Everyone is booked" : "No children waiting",
            onSelect: select
        ) {
            scopeMenu
        } expanded: {
            WaitingStudentsRail(
                viewModel: viewModel,
                coordinator: coordinator,
                filterState: filterState,
                studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
            )
        }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Show", selection: Binding(
                get: { scope },
                set: { scopeRaw = $0.rawValue }
            )) {
                ForEach(WaitingStudentsScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label(scope.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(AppTheme.ScaledFont.captionSemibold)
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Showing \(scope.title)")
    }

    private func select(_ student: CDStudent) {
        guard let id = student.id else { return }
        adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
            if coordinator.selectedStudentFilter == id {
                coordinator.clearStudentFilter()
            } else {
                coordinator.filterByStudent(id)
                filterState.selectedChip = .all
            }
        }
    }
}
