//
//  ClassAreaChecklistView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/22/25.
//

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#endif

struct ClassAreaChecklistView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) private var appRouter
    @State var viewModel = ClassAreaChecklistViewModel()
    @State var didFinishInitialLoad = false
    @State private var isShowingAddWorkSheet = false

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.checklistSelectedArea) private var persistedArea: String = ""

    // Grid Configuration
    let studentColumnWidth: CGFloat = 120
    let lessonColumnWidth: CGFloat = 200
    let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            checklistHeader

            Divider()
            #endif

            filterBar

            Divider()

            if viewModel.isSelectionMode {
                batchActionsToolbar
                Divider()
            }

            if !viewModel.visibleSequences.isEmpty {
                grid
            } else if didFinishInitialLoad {
                emptyState
            } else {
                // Body runs before onAppear; don't flash "no lessons" at a grid that
                // simply hasn't loaded yet.
                Spacer()
            }
        }
        .navigationTitle("Checklist")
        #if os(macOS)
        .toolbar { checklistToolbarContent }
        #endif
        .onAppear {
            // Restore persisted area before loading so loadData uses it
            if !persistedArea.isEmpty {
                viewModel.selectedArea = persistedArea
            }
            // Single load: fetches students, lessons, and builds matrix once
            viewModel.loadData(context: viewContext)
            viewModel.applyVisibilityFilter(
                context: viewContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
            didFinishInitialLoad = true
        }
        .sheet(isPresented: $isShowingAddWorkSheet, onDismiss: {
            viewModel.recomputeMatrix(context: viewContext)
            viewModel.clearSelection()
        }, content: {
            if let lessonID = viewModel.selectedCellsSameLessonID {
                QuickNewWorkItemSheet(
                    preSelectedLessonID: lessonID,
                    preSelectedStudentIDs: viewModel.selectedStudentIDs
                )
            }
        })
        // A request that arrives while the checklist is already on screen never
        // reaches loadData, which only runs on first appearance.
        .onChange(of: appRouter.checklistLessonRequest) { _, request in
            guard let request else { return }
            _ = appRouter.consumeChecklistLessonRequest()
            viewModel.focusLesson(request.lessonID, area: request.area, context: viewContext)
        }
        .onChange(of: viewModel.selectedArea) { _, newValue in
            // Skip during initial load — loadData already built the matrix
            guard didFinishInitialLoad else { return }
            viewModel.refreshMatrix(context: viewContext)
            persistedArea = newValue
        }
        .onChange(of: viewModel.studentFilterIDs) { _, _ in
            viewModel.applyFilters()
        }
        .onChange(of: showTestStudents) { _, _ in
            viewModel.applyVisibilityFilter(
                context: viewContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
        }
        .onChange(of: testStudentNamesRaw) { _, _ in
            viewModel.applyVisibilityFilter(
                context: viewContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
        }
    }
}

// MARK: - macOS Toolbar

extension ClassAreaChecklistView {
    #if os(macOS)
    @ToolbarContentBuilder
    var checklistToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Area", selection: $viewModel.selectedArea) {
                ForEach(viewModel.availableAreas, id: \.self) { area in
                    Text(area).tag(area)
                }
            }
            .pickerStyle(.menu)
            .help("Choose a curriculum area")

            Button(viewModel.isSelectionMode ? "Done" : "Select") {
                withAnimation(.snappy(duration: 0.2)) {
                    if viewModel.isSelectionMode {
                        viewModel.clearSelection()
                    } else {
                        viewModel.isEditModeActive = true
                    }
                }
            }
            .help(viewModel.isSelectionMode ? "Finish selecting checklist cells" : "Select checklist cells")
        }
    }
    #endif
}

// MARK: - Batch Actions Toolbar

extension ClassAreaChecklistView {
    var batchActionsToolbar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedCells.count) selected")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.batchAddToInbox(context: viewContext)
            } label: {
                Label("Add to Inbox", systemImage: "tray")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.batchMarkPresented(context: viewContext)
            } label: {
                Label("Presented", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.batchMarkPreviouslyPresented(context: viewContext)
            } label: {
                Label("Prev. Presented", systemImage: "clock.badge.checkmark")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.batchMarkProficient(context: viewContext)
            } label: {
                Label("Mastered", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(.green)

            if viewModel.selectedCellsSameLessonID != nil {
                Button {
                    isShowingAddWorkSheet = true
                } label: {
                    Label("Add Work", systemImage: "pencil.and.list.clipboard")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Button {
                viewModel.batchClearStatus(context: viewContext)
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button {
                viewModel.clearSelection()
            } label: {
                Text("Done")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.hint))
    }
}

// MARK: - Checklist Header

extension ClassAreaChecklistView {
    var checklistHeader: some View {
        ViewHeader(title: "Checklist") {
            Picker("Area", selection: $viewModel.selectedArea) {
                ForEach(viewModel.availableAreas, id: \.self) { sub in
                    Text(sub).tag(sub)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if viewModel.isSelectionMode {
                        viewModel.clearSelection()
                    } else {
                        viewModel.isEditModeActive = true
                    }
                }
            } label: {
                Text(viewModel.isSelectionMode ? "Done" : "Select")
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
