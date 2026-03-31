// PresentationsListView+Content.swift
// Content rendering extracted from PresentationsListView

import SwiftUI
import CoreData

extension PresentationsListView {
    // MARK: - Content

    var content: some View {
        Group {
            if sort == .upcomingThenPresented {
                if filter == .hiddenUndated {
                    if hiddenUndated.isEmpty {
                        VStack(spacing: 8) {
                            Text("No hidden presentations")
                                .font(AppTheme.ScaledFont.titleMedium)
                            Text("Presentations marked presented without a date will appear here.")
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "eye.slash.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Hidden")
                                        .font(AppTheme.ScaledFont.captionSemibold)
                                        .foregroundStyle(.secondary)
                                }
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                    ForEach(hiddenUndated, id: \.id) { sl in
                                        PresentationCard(
                                                    snapshot: sl.snapshot(),
                                                    lesson: lessonMap[uuidString: sl.lessonID],
                                                    students: students
                                                )
                                            .onTapGesture { selectedLessonID = sl.id }
                                            .contextMenu {
                                                Button {
                                                    quickActionsLessonID = sl.id
                                                } label: {
                                                    Label("Quick Actions…", systemImage: "bolt")
                                                }
                                            }
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let showUpcoming = filter != .completed
                    let showPresented = filter != .notCompleted
                    let up = defaultUpcoming
                    let gv = defaultPresented

                    if (!showUpcoming || up.isEmpty) && (!showPresented || gv.isEmpty) {
                        VStack(spacing: 8) {
                            Text("No presentations")
                                .font(AppTheme.ScaledFont.titleMedium)
                            Text("Try adjusting your filters or add presentations from the Lessons library.")
                                .font(AppTheme.ScaledFont.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if showUpcoming && !up.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "clock")
                                                .foregroundStyle(.secondary)
                                            Text("To Present")
                                                .font(AppTheme.ScaledFont.captionSemibold)
                                                .foregroundStyle(.secondary)
                                        }
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                            ForEach(up, id: \.id) { sl in
                                                PresentationCard(
                                                    snapshot: sl.snapshot(),
                                                    lesson: lessonMap[uuidString: sl.lessonID],
                                                    students: students
                                                )
                                                    .onTapGesture { selectedLessonID = sl.id }
                                                    .contextMenu {
                                                        Button {
                                                            quickActionsLessonID = sl.id
                                                        } label: {
                                                            Label("Quick Actions…", systemImage: "bolt")
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                }
                                if showPresented && !gv.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle")
                                                .foregroundStyle(.secondary)
                                            Text("Given")
                                                .font(AppTheme.ScaledFont.captionSemibold)
                                                .foregroundStyle(.secondary)
                                        }
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                            ForEach(gv, id: \.id) { sl in
                                                PresentationCard(
                                                    snapshot: sl.snapshot(),
                                                    lesson: lessonMap[uuidString: sl.lessonID],
                                                    students: students
                                                )
                                                    .onTapGesture { selectedLessonID = sl.id }
                                                    .contextMenu {
                                                        Button {
                                                            quickActionsLessonID = sl.id
                                                        } label: {
                                                            Label("Quick Actions…", systemImage: "bolt")
                                                        }
                                                    }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                if sortedAssignments.isEmpty {
                    VStack(spacing: 8) {
                        Text("No presentations")
                            .font(AppTheme.ScaledFont.titleMedium)
                        Text("Try adjusting your filters or add presentations from the Lessons library.")
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(sortedAssignments, id: \.id) { sl in
                                PresentationCard(
                                                    snapshot: sl.snapshot(),
                                                    lesson: lessonMap[uuidString: sl.lessonID],
                                                    students: students
                                                )
                                    .onTapGesture { selectedLessonID = sl.id }
                                    .contextMenu {
                                        Button {
                                            quickActionsLessonID = sl.id
                                        } label: {
                                            Label("Quick Actions…", systemImage: "bolt")
                                        }
                                    }
                            }
                        }
                        .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
