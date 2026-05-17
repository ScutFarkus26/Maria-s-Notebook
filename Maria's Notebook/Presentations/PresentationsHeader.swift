// PresentationsHeader.swift
// Screen-level header for the Presentations planner: title, search, Filters, Suggest Next.

import SwiftUI

struct PresentationsHeader: View {
    let filterState: PresentationsFilterState
    let coordinator: PresentationsCoordinator
    let cachedStudents: [CDStudent]
    let isSuggestEnabled: Bool
    let onSuggestNext: () -> Void
    let onFilters: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            titleBar
            searchBar
            committedFilterChipsRow
            activeStudentFilterChip
        }
        .padding(.bottom, AppTheme.Spacing.small)
    }

    private var titleBar: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
            Text("Presentations")
                .font(.title3.weight(.semibold))

            Spacer()

            Button(action: onFilters) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(action: onSuggestNext) {
                Label("Suggest Next", systemImage: "sparkles")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(!isSuggestEnabled)

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
}
