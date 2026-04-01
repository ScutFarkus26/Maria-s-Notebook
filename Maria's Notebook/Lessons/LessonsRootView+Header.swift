// LessonsRootView+Header.swift
// Header trailing controls extracted to keep LessonsRootView type body within limits.

import SwiftUI
import CoreData

extension LessonsRootView {
    // MARK: - Header Controls

    @ViewBuilder
    var headerTrailingControls: some View {
        HStack(spacing: 12) {
            if isJiggling {
                Button {
                    adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isJiggling = false
                    }
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Picker("Mode", selection: Binding(
                    get: { displayMode },
                    set: { displayModeRaw = $0.rawValue }
                )) {
                    ForEach(LessonsDisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .disabled(selectedSubject == nil)

                Menu {
                    Button {
                        showingAddLesson = true
                    } label: {
                        Label("New CDLesson", systemImage: "plus.circle")
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
    }
}
