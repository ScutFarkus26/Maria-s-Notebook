// GroupListView.swift
// Column 2 of the 3-column NavigationSplitView: Displays groups/tracks for the selected subject.
// Groups are derived from existing Lesson data using LessonsViewModel.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GroupListView: View {
    let groups: [String]
    let selectedSubject: String?
    let selectedGroup: String?
    let onSelectGroup: (String?) -> Void
    let onReorderGroups: ((IndexSet, Int) -> Void)?
    var onRenameGroup: ((String) -> Void)?
    #if os(iOS)
    @Binding var editMode: EditMode
    #else
    let isReorderMode: Bool
    #endif

    var body: some View {
        Group {
            if groups.isEmpty {
                emptyStateView
            } else {
                listView
            }
        }
        .navigationTitle(selectedSubject ?? "Groups")
        #if os(iOS)
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var listView: some View {
        List(selection: Binding(
            get: { selectedGroup },
            set: { onSelectGroup($0) }
        )) {
            ForEach(groups, id: \.self) { group in
                GroupListRow(
                    group: group,
                    subject: selectedSubject
                )
                .tag(group)
                .contextMenu {
                    Button {
                        onSelectGroup(group)
                    } label: {
                        Label("View Lessons", systemImage: SFSymbol.Education.book)
                    }

                    if let onRename = onRenameGroup {
                        Button {
                            onRename(group)
                        } label: {
                            Label("Rename Group", systemImage: SFSymbol.Education.pencil)
                        }
                    }

                    Divider()

                    Button {
                        copyGroupName(group)
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                }
            }
            .onMove(perform: onReorderGroups)
        }
        .listStyle(.sidebar)
    }

    private func copyGroupName(_ group: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(group, forType: .string)
        #else
        UIPasteboard.general.string = group
        #endif
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No groups")
                .font(AppTheme.ScaledFont.titleSmall)
            Text("Select a subject to view groups")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GroupListRow: View {
    let group: String
    let subject: String?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .foregroundStyle(subjectColor)
                .font(.system(size: 16))
            Text(group.isEmpty ? "Ungrouped" : group)
                .font(AppTheme.ScaledFont.body)
        }
        .padding(.vertical, 4)
    }
    
    private var subjectColor: Color {
        if let subject {
            return AppColors.color(forSubject: subject)
        }
        return .secondary
    }
}
