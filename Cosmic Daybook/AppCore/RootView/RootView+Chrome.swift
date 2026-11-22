// RootView+Chrome.swift
// The window chrome around RootView's content: the iPhone context bar, the
// search / sync overlay, and the warning banners.

import SwiftUI

extension RootView {
    #if os(iOS)
    /// One line on iPhone. While Sample Class is showing, the bar itself turns
    /// blue and carries the way back, so the separate Sample Class banner (which
    /// wrapped to four lines at phone width) isn't stacked on top of it.
    var mobileContextBar: some View {
        HStack(spacing: 10) {
            MobileClassroomAndYearPicker(
                workspaceStore: classroomWorkspace,
                showsContextLabel: true,
                choose: { requestClassroomSwitch(to: $0) }
            )
            .layoutPriority(1)

            Spacer(minLength: 8)

            if classroomWorkspace.isShowingSampleClass {
                Button("Exit Sample") {
                    requestClassroomSwitch(to: .myClass)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Return to My Class")
                .accessibilityHint("Sample Class practice data is separate from My Class.")
            }

            Button {
                activeSheet = .search
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            CompactSyncStatusIndicator(compact: true)
                .opacity(classroomWorkspace.isShowingSampleClass ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if classroomWorkspace.isShowingSampleClass {
                Rectangle().fill(.bar).overlay(Color.blue.opacity(0.12))
            } else {
                Rectangle().fill(.bar)
            }
        }
    }
    #endif

    /// The corner controls (`RootCornerControls`) acting in this window.
    func cornerControls(showsSchoolYear: Bool) -> RootCornerControls {
        RootCornerControls(
            workspaceStore: classroomWorkspace,
            showsSchoolYear: showsSchoolYear,
            switchClassroom: { requestClassroomSwitch(to: $0) },
            openSearch: { activeSheet = .search }
        )
    }

    var searchAndSyncOverlay: some View {
        cornerControls(showsSchoolYear: selectedNavItem != .today)
            .padding(.trailing, 12)
            .padding(.top, 6)
    }

    @ViewBuilder
    var warningBanners: some View {
        if classroomWorkspace.isShowingSampleClass, !showsSampleStateInContextBar {
            SampleClassroomBanner { requestClassroomSwitch(to: .myClass) }
        }

        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
            EphemeralStoreWarningBanner()
        }

        let cloudStatus = CloudKitConfiguration.getCloudKitStatus()
        if !classroomWorkspace.isShowingSampleClass,
           cloudStatus.enabled && !cloudStatus.active {
            CloudKitSyncWarningBanner()
        }

        if !dependencies.schoolYearStore.isCurrentYearSelected {
            SchoolYearBanner()
        }
    }
}
