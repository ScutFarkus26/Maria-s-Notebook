// StudentDetailTabNavigation.swift
// Tab navigation component extracted from StudentDetailView

import SwiftUI
import CoreData

enum StudentDetailTab: String {
    case overview, meetings, notes, progress, developmentalTraits, history, files
}

struct StudentDetailTabNavigation: View {
    @Binding var selectedTab: StudentDetailTab

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(iOS)
        Group {
            if horizontalSizeClass == .compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        compactTabButtons
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 8)
            } else {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        tabButtons
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        #else
        HStack {
            Spacer()
            HStack(spacing: 12) {
                tabButtons
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        #endif
    }

    // MARK: - Standard Tab Buttons (iPad/macOS)
    @ViewBuilder
    private var tabButtons: some View {
        PillButton(title: "Overview", isSelected: selectedTab == .overview) {
            selectedTab = .overview
        }
        PillButton(title: "Meetings", isSelected: selectedTab == .meetings) {
            selectedTab = .meetings
        }
        PillButton(title: "Notes", isSelected: selectedTab == .notes) {
            selectedTab = .notes
        }
        PillButton(title: "Progress", isSelected: selectedTab == .progress) {
            selectedTab = .progress
        }
        PillButton(title: "Traits", isSelected: selectedTab == .developmentalTraits) {
            selectedTab = .developmentalTraits
        }
        PillButton(title: "History", isSelected: selectedTab == .history) {
            selectedTab = .history
        }
        PillButton(title: "Files", isSelected: selectedTab == .files) {
            selectedTab = .files
        }
    }

    // MARK: - Compact Tab Buttons (iPhone) - Icons with short labels
    #if os(iOS)
    @ViewBuilder
    private var compactTabButtons: some View {
        CompactPillButton(
            title: "Overview",
            systemImage: "person.crop.circle",
            isSelected: selectedTab == .overview
        ) {
            selectedTab = .overview
        }
        CompactPillButton(
            title: "Meetings",
            systemImage: "calendar",
            isSelected: selectedTab == .meetings
        ) {
            selectedTab = .meetings
        }
        CompactPillButton(
            title: "Notes",
            systemImage: "note.text",
            isSelected: selectedTab == .notes
        ) {
            selectedTab = .notes
        }
        CompactPillButton(
            title: "Progress",
            systemImage: "chart.line.uptrend.xyaxis",
            isSelected: selectedTab == .progress
        ) {
            selectedTab = .progress
        }
        CompactPillButton(
            title: "Traits",
            systemImage: "leaf.fill",
            isSelected: selectedTab == .developmentalTraits
        ) {
            selectedTab = .developmentalTraits
        }
        CompactPillButton(
            title: "History",
            systemImage: "clock.arrow.circlepath",
            isSelected: selectedTab == .history
        ) {
            selectedTab = .history
        }
        CompactPillButton(
            title: "Files",
            systemImage: "folder",
            isSelected: selectedTab == .files
        ) {
            selectedTab = .files
        }
    }
    #endif
}

// MARK: - Compact Pill Button (iPhone-optimized)
#if os(iOS)
private struct CompactPillButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.secondary.opacity(UIConstants.OpacityConstants.light))
            )
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
#endif
