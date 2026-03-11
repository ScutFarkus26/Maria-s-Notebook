//
//  ClassSubjectChecklistView.swift
//  Maria's Notebook
//
//  Created by Danny De Berry on 12/22/25.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct ClassSubjectChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ClassSubjectChecklistViewModel()
    @State private var didFinishInitialLoad = false
    @State private var isShowingAddWorkSheet = false

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.checklistSelectedSubject) private var persistedSubject: String = ""

    // Grid Configuration
    private let studentColumnWidth: CGFloat = 120
    private let lessonColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Page Header / Controls
            ViewHeader(title: "Checklist") {
                Picker("Subject", selection: $viewModel.selectedSubject) {
                    ForEach(viewModel.availableSubjects, id: \.self) { sub in
                        Text(sub).tag(sub)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            Divider()

            // MARK: - Batch Actions Toolbar
            if viewModel.isSelectionMode {
                HStack(spacing: 12) {
                    Text("\(viewModel.selectedCells.count) selected")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        viewModel.batchAddToInbox(context: modelContext)
                    } label: {
                        Label("Add to Inbox", systemImage: "tray")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.batchMarkPresented(context: modelContext)
                    } label: {
                        Label("Presented", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.batchMarkPreviouslyPresented(context: modelContext)
                    } label: {
                        Label("Prev. Presented", systemImage: "clock.badge.checkmark")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.batchMarkProficient(context: modelContext)
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
                        viewModel.batchClearStatus(context: modelContext)
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
                .background(Color.accentColor.opacity(0.05))

                Divider()
            } else {
                // Hint for selection mode when not active
                HStack {
                    Spacer()
                    #if os(iOS)
                    Text("Tip: Long press a cell or use context menu to select multiple")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    #else
                    Text("Tip: Long press or right-click to select multiple cells")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    #endif
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // MARK: - 2D Scrollable Grid with Pinned Header
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Data Rows
                        ForEach(viewModel.orderedGroups, id: \.self) { group in
                            // Group Header
                            HStack(spacing: 0) {
                                StickyLeftItem(width: lessonColumnWidth, height: 30) {
                                    HStack {
                                        Text(group)
                                            .font(.system(.caption, design: .rounded).weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading)
                                        Spacer()
                                    }
                                    .background(Color.secondary.opacity(0.05))
                                    .borderSeparated()
                                }

                                // Spacer for the rest of the group row
                                Color.secondary.opacity(0.05)
                                    .frame(height: 30)
                                    .frame(width: CGFloat(viewModel.students.count) * studentColumnWidth)
                                    .borderSeparated()
                            }

                            let lessons = viewModel.lessonsIn(group: group)
                            ForEach(lessons) { lesson in
                                HStack(spacing: 0) {
                                    // Lesson Name (Sticky Left)
                                    StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                                        VStack(alignment: .leading) {
                                            Text(lesson.name)
                                                .font(.system(.body, design: .rounded).weight(.medium))
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.9)
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(width: lessonColumnWidth, height: rowHeight, alignment: .leading)
                                        .backgroundPlatform()
                                        .borderSeparated()
                                    }

                                    // Grid Cells
                                    ForEach(viewModel.students) { student in
                                        let state = viewModel.state(for: student, lesson: lesson)
                                        ClassChecklistSmartCell(
                                            state: state,
                                            isSelected: viewModel.isSelected(student: student, lesson: lesson),
                                            isSelectionMode: viewModel.isSelectionMode,
                                            onTap: {
                                                viewModel.toggleScheduled(
                                                    student: student, lesson: lesson, context: modelContext
                                                )
                                            },
                                            onSelect: {
                                                viewModel.toggleSelection(student: student, lesson: lesson)
                                            },
                                            onMarkComplete: {
                                                viewModel.markComplete(
                                                    student: student, lesson: lesson, context: modelContext
                                                )
                                            },
                                            onMarkPresented: {
                                                viewModel.togglePresented(
                                                    student: student, lesson: lesson, context: modelContext
                                                )
                                            },
                                            onMarkPreviouslyPresented: {
                                                viewModel.togglePreviouslyPresented(
                                                    student: student, lesson: lesson, context: modelContext
                                                )
                                            },
                                            onClear: {
                                                viewModel.clearStatus(
                                                    student: student, lesson: lesson, context: modelContext
                                                )
                                            }
                                        )
                                        .frame(width: studentColumnWidth, height: rowHeight)
                                        .borderSeparated()
                                    }
                                }
                            }
                        }
                    } header: {
                        // Pinned header row - stays at top during vertical scroll
                        headerRow
                    }
                }
            }
            .coordinateSpace(name: "gridSpace")
        }
        .onAppear {
            // Restore persisted subject before loading so loadData uses it
            if !persistedSubject.isEmpty {
                viewModel.selectedSubject = persistedSubject
            }
            // Single load: fetches students, lessons, and builds matrix once
            viewModel.loadData(context: modelContext)
            viewModel.applyVisibilityFilter(
                context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
            didFinishInitialLoad = true
        }
        .sheet(isPresented: $isShowingAddWorkSheet, onDismiss: {
            viewModel.recomputeMatrix(context: modelContext)
            viewModel.clearSelection()
        }, content: {
            if let lessonID = viewModel.selectedCellsSameLessonID {
                QuickNewWorkItemSheet(
                    preSelectedLessonID: lessonID,
                    preSelectedStudentIDs: viewModel.selectedStudentIDs
                )
            }
        })
        .onChange(of: viewModel.selectedSubject) { _, newValue in
            // Skip during initial load — loadData already built the matrix
            guard didFinishInitialLoad else { return }
            viewModel.refreshMatrix(context: modelContext)
            persistedSubject = newValue
        }
        .onChange(of: showTestStudents) { _, _ in
            viewModel.applyVisibilityFilter(
                context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
        }
        .onChange(of: testStudentNamesRaw) { _, _ in
            viewModel.applyVisibilityFilter(
                context: modelContext, show: showTestStudents, namesRaw: testStudentNamesRaw
            )
        }
    }

}

// MARK: - Header Row

extension ClassSubjectChecklistView {
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Top-Left Corner (Sticky horizontally)
            StickyLeftItem(width: lessonColumnWidth, height: rowHeight) {
                ZStack {
                    Color.clear.backgroundPlatform()
                    Text("Lessons \\ Students")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: lessonColumnWidth, height: rowHeight)
                .borderSeparated()
            }
            .zIndex(100) // Ensure corner stays above everything

            // Student Names (Scrolls Horizontally with content, tappable)
            ForEach(viewModel.students) { student in
                Button {
                    AppRouter.shared.requestOpenStudentDetail(student.id)
                } label: {
                    VStack(spacing: 2) {
                        Text(viewModel.displayName(for: student))
                        Text(AgeUtils.conciseAgeString(for: student.birthday))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: studentColumnWidth, height: rowHeight)
                    .backgroundPlatform()
                    .borderSeparated()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(
            minWidth: lessonColumnWidth + (CGFloat(viewModel.students.count) * studentColumnWidth),
            alignment: .leading
        )
    }
}
