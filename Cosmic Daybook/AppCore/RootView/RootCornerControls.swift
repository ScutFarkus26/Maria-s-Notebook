// RootCornerControls.swift
// The class control, the school-year picker, search and the sync dot that sit
// in the top-right corner over the iPad's pages (RootView's corner overlay).

import SwiftUI

struct RootCornerControls: View {
    let workspaceStore: ClassroomWorkspaceStore
    /// Off on Today, whose date controls stand in for the year.
    var showsSchoolYear = true
    let switchClassroom: (ClassroomWorkspace) -> Void
    let openSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            classroomPicker
            if showsSchoolYear {
                SchoolYearPicker()
            }
            searchButton
            syncDot
        }
    }

    /// The pieces one by one, for a toolbar, which gives each its own item.
    var classroomPicker: some View {
        ClassroomWorkspacePicker(workspaceStore: workspaceStore, choose: switchClassroom)
    }

    var searchButton: some View {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        #if os(macOS)
        .help("Search notes, lessons, students, and todos (⌘F)")
        #endif
    }

    var syncDot: some View {
        CompactSyncStatusIndicator(compact: true)
            .opacity(workspaceStore.isShowingSampleClass ? 0 : 1)
    }
}

#if os(iOS)
extension EnvironmentValues {
    /// The corner controls for Today's own toolbar, on the iPad layouts that
    /// draw them in the corner (not the iPhone or iPad mini, whose context bar
    /// carries them). Today's trailing toolbar items (‹ Today ›, Go to Date, +)
    /// sat under the corner overlay, so RootView leaves the overlay off there
    /// and Today shows these at its bar's leading end instead, where the iPad
    /// 11-inch has room (its trailing end already folds Go to Date and + into
    /// the overflow menu). Nil elsewhere.
    @Entry var todayCornerControls: RootCornerControls?
}

/// The corner controls in Today's toolbar, at its leading end. One item each:
/// a toolbar showed the three in one item as a bare class icon, without search
/// or the sync dot.
struct TodayCornerToolbarItems: ToolbarContent {
    let controls: RootCornerControls

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            controls.classroomPicker
        }
        ToolbarItem(placement: .topBarLeading) {
            controls.searchButton
        }
        ToolbarItem(placement: .topBarLeading) {
            controls.syncDot
        }
    }
}
#endif
