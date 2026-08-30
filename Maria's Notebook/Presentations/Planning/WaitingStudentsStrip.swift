// WaitingStudentsStrip.swift
// The waiting list on a phone: one scrolling row of names above the lessons.
//
// A 240pt column is impossible here, but making it a separate tab would be
// worse — the whole point is seeing who has waited *while* looking at what you
// could give them. So the same list, same order, laid on its side, costing one
// row of height.
//
// A long roster becomes a long swipe, so the scope control and an "All" button
// are pinned outside the scroll and always reachable.

import SwiftUI

struct WaitingStudentsStrip: View {
    let viewModel: PresentationsViewModel
    let coordinator: PresentationsCoordinator
    let filterState: PresentationsFilterState
    let studentIDsWithUpcomingLessons: Set<UUID>

    @SceneStorage("Presentations.waitingScope")
    private var scopeRaw: String = WaitingStudentsScope.everyone.rawValue
    @State private var isShowingAll = false

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
        HStack(spacing: AppTheme.Spacing.small) {
            scopeMenu

            if entries.isEmpty {
                Text(scope == .unscheduled ? "Everyone is booked" : "No children waiting")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: AppTheme.Spacing.verySmall) {
                        ForEach(entries) { entry in
                            chip(entry)
                        }
                    }
                    .padding(.trailing, AppTheme.Spacing.small)
                }
                .scrollIndicators(.hidden)

                allStudentsButton
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .sheet(isPresented: $isShowingAll) {
            NavigationStack {
                WaitingStudentsRail(
                    viewModel: viewModel,
                    coordinator: coordinator,
                    filterState: filterState,
                    studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
                )
                .navigationTitle("Waiting Longest")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingAll = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .fixedSize()
        .accessibilityLabel("Showing \(scope.title)")
    }

    /// The escape from a thirty-child swipe.
    private var allStudentsButton: some View {
        Button {
            isShowingAll = true
        } label: {
            Text("All")
                .font(AppTheme.ScaledFont.captionSemibold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .fixedSize()
        .accessibilityLabel("Show every waiting child")
    }

    private func chip(_ entry: WaitingStudent) -> some View {
        let isSelected = coordinator.selectedStudentFilter == entry.student.id
        return Button {
            select(entry.student)
        } label: {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                // A capsule has no leading edge to run a bar down, so the same
                // urgency colour becomes a dot.
                Circle()
                    .fill(WaitingStudentsStrip.urgencyColor(for: entry))
                    .frame(width: 6, height: 6)
                Text(StudentFormatter.firstName(for: entry.student))
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(entry.daysWaiting.map { "\($0)d" } ?? "—")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                        : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                )
            )
            .overlay {
                if isSelected {
                    Capsule().stroke(
                        Color.accentColor.opacity(UIConstants.OpacityConstants.half),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(StudentFormatter.displayName(for: entry.student)), "
                + (entry.daysWaiting.map { "\($0) school days since a lesson" } ?? "never taught")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Matches `WaitingStudentRow`'s bar, using the shipped thresholds — the
    /// strip is too small to justify five more `@SyncedAppStorage` reads.
    static func urgencyColor(for entry: WaitingStudent) -> Color {
        guard let days = entry.daysWaiting else {
            return ColorUtils.color(from: LessonAgeDefaults.overdueColorHex)
        }
        if days >= LessonAgeDefaults.overdueDays {
            return ColorUtils.color(from: LessonAgeDefaults.overdueColorHex)
        }
        if days >= LessonAgeDefaults.warningDays {
            return ColorUtils.color(from: LessonAgeDefaults.warningColorHex)
        }
        return ColorUtils.color(from: LessonAgeDefaults.freshColorHex)
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
