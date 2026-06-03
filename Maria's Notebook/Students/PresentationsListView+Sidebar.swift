// PresentationsListView+Sidebar.swift
// Sidebar extracted from PresentationsListView

import SwiftUI
import CoreData

extension PresentationsListView {
    // MARK: - Sidebar

    var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                completionFilters
                areaFilters

                Divider()

                hiddenFilter

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading)
        #if os(macOS)
        .frame(width: 200)
        #endif
        .background(Color.gray.opacity(UIConstants.OpacityConstants.subtle))
    }

    private var completionFilters: some View {
        Group {
            sidebarSectionHeader("Filters")

            filterButton(icon: "line.3.horizontal.decrease.circle",
                         title: CompletionFilter.all.rawValue,
                         color: .accentColor,
                         isSelected: filter == .all,
                         filterValue: "all")

            filterButton(icon: "checkmark.circle.fill",
                         title: CompletionFilter.completed.rawValue,
                         color: .green,
                         isSelected: filter == .completed,
                         filterValue: "completed")

            filterButton(icon: "circle.dashed",
                         title: CompletionFilter.notCompleted.rawValue,
                         color: .orange,
                         isSelected: filter == .notCompleted,
                         filterValue: "notCompleted")
        }
    }

    private var areaFilters: some View {
        Group {
            sidebarSectionHeader("Area")

            SidebarFilterButton(
                icon: "rectangle.3.sequence",
                title: "All Areas",
                color: .accentColor,
                isSelected: selectedArea == nil
            ) {
                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    presentationsAreaRaw = ""
                }
            }

            ForEach(areas, id: \.self) { area in
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: area,
                    color: AppColors.color(forArea: area),
                    isSelected: selectedArea?.caseInsensitiveCompare(area) == .orderedSame
                ) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        presentationsAreaRaw = area
                    }
                }
            }
        }
    }

    private var hiddenFilter: some View {
        SidebarFilterButton(
            icon: "eye.slash.fill",
            title: CompletionFilter.hiddenUndated.rawValue,
            color: .gray,
            isSelected: filter == .hiddenUndated
        ) {
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                if filter == .hiddenUndated {
                    presentationsFilterRaw = previousPresentationsFilterRaw ?? "all"
                } else {
                    previousPresentationsFilterRaw = presentationsFilterRaw
                    presentationsFilterRaw = "hidden"
                }
            }
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.ScaledFont.captionSemibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }

    private func filterButton(
        icon: String,
        title: String,
        color: Color,
        isSelected: Bool,
        filterValue: String
    ) -> some View {
        SidebarFilterButton(icon: icon, title: title, color: color, isSelected: isSelected) {
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                presentationsFilterRaw = filterValue
            }
        }
    }
}
