//
//  ClassAreaChecklistView.swift
//  Cosmic Daybook
//
//  Created by Danny De Berry on 12/22/25.
//

import SwiftUI
import CoreData

struct ClassAreaChecklistView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) private var appRouter
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State var viewModel = ClassAreaChecklistViewModel()
    @State var didFinishInitialLoad = false
    /// The new-work sheet: from the card's Assign Work, or the selection's Add Work.
    @State var workTarget: ChecklistWorkTarget?
    /// The present-a-lesson sheet, for a draft made from the card or the selection.
    @State var presentationTarget: ChecklistPresentationTarget?
    /// The pointer's row and column, read only by the tints and the names it emphasizes.
    @State var hover = ChecklistHoverState()
    /// The grid's visible width, so the lesson column can narrow to fit the class.
    @State var gridViewportWidth: CGFloat = 0
    /// The plain keys work while the grid has focus (+Keyboard).
    @FocusState var isGridFocused: Bool
    /// The selection a drag started from, while the drag lasts (+Selection).
    @State var dragBase: Set<CellIdentifier>?
    /// A pick from "Jump to sequence", for the grid to scroll to.
    @State var sequenceJump: ChecklistSequenceJump?
    /// The grid's visible height, read once per resize, to land a jumped-to band just
    /// under the pinned header rather than behind it.
    @State var gridViewportHeight: CGFloat = 0

    @TestStudentVisibility private var testStudents
    @AppStorage(UserDefaultsKeys.checklistSelectedArea) private var persistedArea: String = ""

    /// The Mac and a regular-width iPad get the dense layout and the toolbar; an iPhone
    /// keeps its header, filter bar and wide columns (plan, decision 3).
    var usesRegularLayout: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    /// On the Mac and iPad the lesson column narrows (to 200 pt) so the whole class and the
    /// Class column fit the window: 22 children fit 1180 pt.
    var metrics: ChecklistGridMetrics {
        usesRegularLayout
            ? ChecklistGridMetrics.regular.fitted(toWidth: gridViewportWidth, studentCount: viewModel.students.count)
            : .compact
    }

    var body: some View {
        page
            .onAppear {
                // Restore persisted area before loading so loadData uses it
                if !persistedArea.isEmpty {
                    viewModel.selectedArea = persistedArea
                }
                // Single load: fetches students, lessons, and builds matrix once
                viewModel.loadData(context: viewContext)
                viewModel.applyVisibilityFilter(
                    context: viewContext, show: testStudents.show, namesRaw: testStudents.namesRaw
                )
                didFinishInitialLoad = true
            }
            .sheet(item: $workTarget) { target in
                QuickNewWorkItemSheet(
                    preSelectedLessonID: target.lessonID,
                    preSelectedStudentIDs: target.studentIDs
                )
                .onDisappear { finishSheet(fromSelection: target.fromSelection) }
            }
            .sheet(item: $presentationTarget) { target in
                PresentationDetailView(lessonAssignment: target.assignment) { presentationTarget = nil }
                    .studentDetailSheetSizing()
                    .onDisappear { finishPresentation(target) }
            }
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
            .onChange(of: testStudents.show) { _, _ in
                viewModel.applyVisibilityFilter(
                    context: viewContext, show: testStudents.show, namesRaw: testStudents.namesRaw
                )
            }
            .onChange(of: testStudents.namesRaw) { _, _ in
                viewModel.applyVisibilityFilter(
                    context: viewContext, show: testStudents.show, namesRaw: testStudents.namesRaw
                )
            }
            // Changes synced in from another device; onAppear already reloads on return.
            .onReceiveWhenVisible(Self.remoteRecordChanges(), catchUpOnAppear: false) {
                guard didFinishInitialLoad else { return }
                viewModel.refreshMatrix(context: viewContext)
            }
    }

    @ViewBuilder
    private var page: some View {
        if usesRegularLayout {
            regularPage
        } else {
            compactPage
        }
    }

    /// iPhone: the header with the area picker, the lens menu and Select, then the filter bar.
    private var compactPage: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            checklistHeader

            Divider()
            #endif

            filterBar

            Divider()

            checklistBody
        }
        .navigationTitle("Checklist")
    }

    /// The selection bar, the grid and its key, or the empty state. Both layouts: the iPhone's
    /// selection bar sits on top, the Mac and iPad's floats over the grid's foot.
    var checklistBody: some View {
        VStack(spacing: 0) {
            if viewModel.isSelectionMode && !usesRegularLayout {
                batchActionsToolbar
                Divider()
            }

            if !viewModel.visibleSequences.isEmpty {
                grid
                    .overlay(alignment: .bottom) {
                        if usesRegularLayout && !viewModel.selectedCells.isEmpty {
                            floatingSelectionBar
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: viewModel.selectedCells.isEmpty)
                Divider()
                ChecklistStatusBar(
                    counts: viewModel.statusCounts,
                    lessonCount: viewModel.visibleLessons.count,
                    studentCount: viewModel.students.count,
                    lens: viewModel.lens
                )
            } else if didFinishInitialLoad {
                emptyState
            } else {
                // Body runs before onAppear; don't flash "no lessons" at a grid that
                // simply hasn't loaded yet.
                Spacer()
            }
        }
    }
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
                    performSelectionAction(.addWork)
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

            ChecklistLensMenu(lens: $viewModel.lens, readyCount: viewModel.readyTotal)

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
