// PresentationsHeader.swift
// Screen-level header for the Presentations planner: title, search, Suggest Next, overflow menu.

import SwiftUI

struct PresentationsHeader: View {
    let filterState: PresentationsFilterState
    let coordinator: PresentationsCoordinator
    let cachedStudents: [CDStudent]
    let isSuggestEnabled: Bool
    let onSuggestNext: () -> Void
    let onFilters: () -> Void
    let onConsolidate: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            titleBar
            searchBar
            committedFilterChipsRow
            activeStudentFilterChip
            legendRow
        }
        .padding(.bottom, AppTheme.Spacing.small)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
            Text("Presentations")
                .font(.title3.weight(.semibold))

            Spacer()

            Button(action: onSuggestNext) {
                Label("Suggest Next", systemImage: "sparkles")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(!isSuggestEnabled)

            overflowMenu

            #if os(iOS)
            Button {
                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    coordinator.toggleCalendar()
                }
            } label: {
                Image(systemName: coordinator.isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(AppTheme.Spacing.small)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.light))
                    .clipShape(Circle())
            }
            #endif
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.top, AppTheme.Spacing.small)
    }

    // MARK: - Overflow menu

    /// Tint the ellipsis icon with accent when any toggle inside is active,
    /// so the user can tell a filter is set without opening the menu.
    private var overflowMenuTint: Color {
        filterState.hideStudentsScheduledToday ? Color.accentColor : .secondary
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onFilters) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }

            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    filterState.hideStudentsScheduledToday.toggle()
                }
            } label: {
                if filterState.hideStudentsScheduledToday {
                    Label("Showing Today's Students", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    Label("Hide Today's Students", systemImage: "person.crop.circle.badge.clock")
                }
            }

            Button(action: onConsolidate) {
                Label("Consolidate", systemImage: "arrow.triangle.merge")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(overflowMenuTint)
                .accessibilityLabel("More options")
        }
        .menuStyle(.automatic)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)

            TextField(
                "Search presentations, students, or topics…",
                text: Binding(
                    get: { filterState.searchText },
                    set: { filterState.updateSearchText($0) }
                )
            )
            .textFieldStyle(.plain)
            .onSubmit {
                filterState.commitCurrentSearchAsFilter()
            }
            .onKeyPress(.return) {
                filterState.commitCurrentSearchAsFilter()
                return .handled
            }
            .onKeyPress(.delete) {
                if filterState.searchText.isEmpty, !filterState.committedFilters.isEmpty {
                    filterState.popLastFilter()
                    return .handled
                }
                return .ignored
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
        .padding(.horizontal, AppTheme.Spacing.medium)
    }

    // MARK: - Committed filter chips

    @ViewBuilder
    private var committedFilterChipsRow: some View {
        if !filterState.committedFilters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    ForEach(filterState.committedFilters, id: \.self) { token in
                        searchTokenChip(token)
                    }
                    Button {
                        filterState.clearFilters()
                    } label: {
                        Text("Clear all")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, AppTheme.Spacing.verySmall)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
            }
        }
    }

    private func searchTokenChip(_ token: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            Text(token)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Button {
                filterState.removeFilter(token)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xxsmall)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var activeStudentFilterChip: some View {
        if let studentID = coordinator.selectedStudentFilter,
           let student = cachedStudents.first(where: { $0.id == studentID }) {
            studentFilterChipContent(student)
        }
    }

    private func studentFilterChipContent(_ student: CDStudent) -> some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Text(StudentFormatter.displayName(for: student))
                .font(.caption.weight(.medium))
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    coordinator.clearStudentFilter()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColors.warning)
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .background(AppColors.warning.opacity(UIConstants.OpacityConstants.accent))
        .clipShape(Capsule())
        .padding(.horizontal, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Color legend

    private var legendRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.compact) {
                legendLabel("Status")
                legendSwatch(AppColors.color(for: .overdue), "Overdue")
                legendSwatch(AppColors.color(for: .brewing), "Brewing")
                legendSwatch(Color.accentColor, "Suggested")

                legendDivider

                legendLabel("Subject")
                legendSwatch(AppColors.color(forArea: "math"), "Math")
                legendSwatch(AppColors.color(forArea: "language"), "Language")
                legendSwatch(AppColors.color(forArea: "science"), "Science")
                legendSwatch(AppColors.color(forArea: "practical life"), "Practical Life")
                legendSwatch(AppColors.color(forArea: "sensorial"), "Sensorial")
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.xxsmall)
        }
    }

    private func legendLabel(_ text: String) -> some View {
        Text(text + ":")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private var legendDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 10)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
