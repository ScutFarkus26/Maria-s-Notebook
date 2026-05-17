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
            headerModePicker
            headerAddMenu
        }
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

    private var headerModePicker: some View {
        Picker("Mode", selection: Binding(
            get: { displayMode },
            set: { displayModeRaw = $0.rawValue }
        )) {
            ForEach(LessonsDisplayMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    private var headerAddMenu: some View {
        Menu {
            Button {
                showingAddLesson = true
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
