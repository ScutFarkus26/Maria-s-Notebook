// LessonsRootView+Header.swift
// Header trailing controls extracted to keep LessonsRootView type body within limits.

import SwiftUI
import CoreData

extension LessonsRootView {
    // MARK: - Header Controls

    @ViewBuilder
    var headerTrailingControls: some View {
        HStack(spacing: 12) {
            headerSearchField
            parshasToggleButton
            if canShowEditMapButton {
                editMapButton
            }
            headerAddMenu
        }
    }

    private var parshasToggleButton: some View {
        Button {
            showingParshas.toggle()
            if showingParshas {
                isEditingMap = false
                focusedThread = nil
                selectedLessonDetail = nil
            }
        } label: {
            Label("Parshas", systemImage: showingParshas ? "scroll.fill" : "scroll")
        }
        .buttonStyle(.bordered)
        .tint(showingParshas ? .indigo : nil)
        .help(showingParshas ? "Back to lessons map" : "Browse parshas")
    }

    private var editMapButton: some View {
        Button {
            isEditingMap.toggle()
            if isEditingMap { syncReorderableSequences() }
        } label: {
            Label(
                isEditingMap ? "Done" : "Edit",
                systemImage: isEditingMap ? "checkmark" : "arrow.up.arrow.down"
            )
        }
        .buttonStyle(.bordered)
        .tint(isEditingMap ? .accentColor : nil)
        .help(isEditingMap ? "Finish editing" : "Reorder sequences and lessons")
    }

    private var headerSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search lessons", text: $filterState.searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 120, idealWidth: 200, maxWidth: 240)
            if !filterState.searchText.isEmpty {
                Button {
                    filterState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }

    private var headerAddMenu: some View {
        Menu {
            Button {
                addLessonContext = AddLessonContext(source: nil)
            } label: {
                Label("New Lesson", systemImage: "plus.circle")
            }

            Button {
                showingBulkEntry = true
            } label: {
                Label("Bulk Entry…", systemImage: "square.grid.3x3")
            }

            Button {
                appRouter.requestImportLessons()
            } label: {
                Label("Import Lessons…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        #if os(macOS)
        .menuStyle(.borderedButton)
        #endif
    }
}
