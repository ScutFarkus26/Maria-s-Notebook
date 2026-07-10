// StudentDetailTabNavigation.swift
// Tab navigation component extracted from StudentDetailView

import SwiftUI
import CoreData

enum StudentDetailTab: String {
    case overview, meetings, notes, progress, developmentalTraits, history, files, yearPlan

    var group: StudentDetailTabGroup {
        switch self {
        case .overview: return .overview
        case .notes: return .notes
        case .progress, .history, .developmentalTraits, .yearPlan: return .progress
        case .meetings, .files: return .records
        }
    }

    /// Short label used in the sub-tab row inside a group.
    var subTabTitle: String {
        switch self {
        case .overview: return "Overview"
        case .meetings: return "Meetings"
        case .notes: return "Notes"
        case .progress: return "Progress"
        case .developmentalTraits: return "Traits"
        case .history: return "History"
        case .files: return "Files"
        case .yearPlan: return "Year Plan"
        }
    }
}

/// Top-level tab groups: the 8 flat tabs folded into 4 so the row never
/// scrolls off-screen on iPhone. Multi-tab groups show a secondary sub-tab row.
enum StudentDetailTabGroup: CaseIterable {
    case overview
    case notes
    case progress
    case records

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .notes: return "Notes"
        case .progress: return "Progress"
        case .records: return "Records"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "person.crop.circle"
        case .notes: return "note.text"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .records: return "folder"
        }
    }

    var tabs: [StudentDetailTab] {
        switch self {
        case .overview: return [.overview]
        case .notes: return [.notes]
        case .progress: return [.progress, .history, .developmentalTraits, .yearPlan]
        case .records: return [.meetings, .files]
        }
    }

    var defaultTab: StudentDetailTab { tabs[0] }
}

struct StudentDetailTabNavigation: View {
    @Binding var selectedTab: StudentDetailTab

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var selectedGroup: StudentDetailTabGroup { selectedTab.group }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            groupRow
            if selectedGroup.tabs.count > 1 {
                subTabRow
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func selectGroup(_ group: StudentDetailTabGroup) {
        guard selectedGroup != group else { return }
        selectedTab = group.defaultTab
    }

    // MARK: - Group Row

    @ViewBuilder
    private var groupRow: some View {
        if isCompact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    compactGroupButtons
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    ForEach(StudentDetailTabGroup.allCases, id: \.self) { group in
                        PillButton(title: group.title, isSelected: selectedGroup == group) {
                            selectGroup(group)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var compactGroupButtons: some View {
        ForEach(StudentDetailTabGroup.allCases, id: \.self) { group in
            CompactPillButton(
                title: group.title,
                systemImage: group.systemImage,
                isSelected: selectedGroup == group
            ) {
                selectGroup(group)
            }
        }
    }

    // MARK: - Sub-Tab Row

    @ViewBuilder
    private var subTabRow: some View {
        if isCompact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    subTabButtons
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    subTabButtons
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var subTabButtons: some View {
        ForEach(selectedGroup.tabs, id: \.self) { tab in
            SubTabPill(title: tab.subTabTitle, isSelected: selectedTab == tab) {
                selectedTab = tab
            }
        }
    }
}

// MARK: - Compact Pill Button (icon + short label)

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
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                            : Color.secondary.opacity(UIConstants.OpacityConstants.light)
                    )
            )
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sub-Tab Pill (smaller, text-only)

private struct SubTabPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                                : Color.secondary.opacity(UIConstants.OpacityConstants.light)
                        )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
