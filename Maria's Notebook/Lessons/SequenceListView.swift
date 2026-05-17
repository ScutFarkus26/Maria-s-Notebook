// SequenceListView.swift
// Column 2 of the 3-column NavigationSplitView: Displays groups/tracks for the selected area.
// Groups are derived from existing CDLesson data using LessonsViewModel.

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SequenceListView: View {
    let groups: [String]
    let selectedArea: String?
    let selectedSequence: String?
    let onSelectSequence: (String?) -> Void
    let onReorderSequences: ((IndexSet, Int) -> Void)?
    var onRenameSequence: ((String) -> Void)?
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
        .navigationTitle(selectedArea ?? "Sequences")
        #if os(iOS)
        .environment(\.editMode, $editMode)
        .inlineNavigationTitle()
        #endif
    }

    private var listView: some View {
        List(selection: Binding(
            get: { selectedSequence },
            set: { onSelectSequence($0) }
        )) {
            ForEach(groups, id: \.self) { sequence in
                SequenceListRow(
                    sequence: sequence,
                    area: selectedArea
                )
                .tag(sequence)
                .contextMenu {
                    Button {
                        onSelectSequence(sequence)
                    } label: {
                        Label("View Lessons", systemImage: SFSymbol.Education.book)
                    }

                    if let onRename = onRenameSequence {
                        Button {
                            onRename(sequence)
                        } label: {
                            Label("Rename Sequence", systemImage: SFSymbol.Education.pencil)
                        }
                    }

                    Divider()

                    Button {
                        copySequenceName(sequence)
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                }
            }
            .onMove(perform: onReorderSequences)
        }
        .listStyle(.sidebar)
    }

    private func copySequenceName(_ sequence: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sequence, forType: .string)
        #else
        UIPasteboard.general.string = sequence
        #endif
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No groups")
                .font(AppTheme.ScaledFont.titleSmall)
            Text("Select a area to view groups")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SequenceListRow: View {
    let sequence: String
    let area: String?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .foregroundStyle(areaColor)
                .font(.system(size: 16))
            Text(sequence.isEmpty ? "Ungrouped" : sequence)
                .font(AppTheme.ScaledFont.body)
        }
        .padding(.vertical, 4)
    }
    
    private var areaColor: Color {
        if let area {
            return AppColors.color(forArea: area)
        }
        return .secondary
    }
}
