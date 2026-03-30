// PresentationsListView+Sidebar.swift
// Sidebar extracted from PresentationsListView

import SwiftUI

extension PresentationsListView {
    // MARK: - Sidebar

    var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                SidebarFilterButton(
                    icon: "line.3.horizontal.decrease.circle",
                    title: CompletionFilter.all.rawValue,
                    color: .accentColor,
                    isSelected: filter == .all
                ) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        presentationsFilterRaw = "all"
                    }
                }

                SidebarFilterButton(
                    icon: "checkmark.circle.fill",
                    title: CompletionFilter.completed.rawValue,
                    color: .green,
                    isSelected: filter == .completed
                ) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        presentationsFilterRaw = "completed"
                    }
                }

                SidebarFilterButton(
                    icon: "circle.dashed",
                    title: CompletionFilter.notCompleted.rawValue,
                    color: .orange,
                    isSelected: filter == .notCompleted
                ) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        presentationsFilterRaw = "notCompleted"
                    }
                }

                Text("Subject")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                // Clear subject filter
                SidebarFilterButton(
                    icon: "rectangle.3.group",
                    title: "All Subjects",
                    color: .accentColor,
                    isSelected: selectedSubject == nil
                ) {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        presentationsSubjectRaw = ""
                    }
                }

                ForEach(subjects, id: \.self) { subject in
                    SidebarFilterButton(
                        icon: "folder.fill",
                        title: subject,
                        color: AppColors.color(forSubject: subject),
                        isSelected: selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame
                    ) {
                        adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                            presentationsSubjectRaw = subject
                        }
                    }
                }

                Divider()

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

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .topLeading) // FIX: Allow flexible width in sheet
        #if os(macOS)
        .frame(width: 200)
        #endif
        .background(Color.gray.opacity(UIConstants.OpacityConstants.subtle))
    }
}
