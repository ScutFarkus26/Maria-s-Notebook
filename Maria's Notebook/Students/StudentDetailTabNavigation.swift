// StudentDetailTabNavigation.swift
// Tab navigation component extracted from StudentDetailView

import SwiftUI

enum StudentDetailTab: String {
    case overview, checklist, history, meetings, notes, tracks, progress
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
                    HStack(spacing: 12) {
                        tabButtons
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
    
    @ViewBuilder
    private var tabButtons: some View {
        PillButton(title: "Overview", isSelected: selectedTab == .overview) { 
            selectedTab = .overview 
        }
        PillButton(title: "Checklist", isSelected: selectedTab == .checklist) { 
            selectedTab = .checklist 
        }
        PillButton(title: "History", isSelected: selectedTab == .history) { 
            selectedTab = .history 
        }
        PillButton(title: "Meetings", isSelected: selectedTab == .meetings) { 
            selectedTab = .meetings 
        }
        PillButton(title: "Notes", isSelected: selectedTab == .notes) { 
            selectedTab = .notes 
        }
        PillButton(title: "Tracks", isSelected: selectedTab == .tracks) { 
            selectedTab = .tracks 
        }
        PillButton(title: "Progress", isSelected: selectedTab == .progress) { 
            selectedTab = .progress 
        }
    }
}

