// StudentMeetingsTab+WorkSnapshot.swift
// Active work snapshot and lessons-since-last-meeting sections

import SwiftUI
import CoreData

extension StudentMeetingsTab {

    var activeWorkSnapshotSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Work Snapshot")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        // Left column
                        VStack(alignment: .leading, spacing: 6) {
                            rowLine(label: "Open work", value: openWorkCountText)
                            if !openWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(openWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id ?? UUID()
                                            }
                                    }
                                }
                            }
                            rowLine(label: "Overdue/stuck", value: overdueWorkCountText)
                            if !overdueWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(overdueWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id ?? UUID()
                                            }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right column
                        VStack(alignment: .leading, spacing: 6) {
                            rowLine(label: "Recently completed", value: recentlyCompletedWorkCountText)
                            if !recentCompletedWorkModelsForStudent.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(recentCompletedWorkModelsForStudent.prefix(3)) { work in
                                        workRowLine(work, showCompletedDate: true)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedWorkID = work.id ?? UUID()
                                            }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    var lessonsSinceLastMeetingSection: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lessons Since Last Meeting")
                    .font(.headline)
                    .foregroundStyle(.primary)

                let lessonsSinceLastMeeting = lessonsSinceLastMeetingForStudent
                if lessonsSinceLastMeeting.isEmpty {
                    Text("No lessons since last meeting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lessonsSinceLastMeeting) { la in
                            lessonRowLine(la)
                        }
                    }
                }
            }
        }
    }
}
