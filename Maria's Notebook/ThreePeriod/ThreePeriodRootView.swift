// ThreePeriodRootView.swift
// Main view for the Three-Period Lesson Tracker.

import SwiftUI
import SwiftData

struct ThreePeriodRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ThreePeriodViewModel()

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if viewModel.summaries.isEmpty {
                ContentUnavailableView(
                    "No Lesson Presentations",
                    systemImage: "3.circle",
                    description: Text("Present lessons to students to see their three-period progress here.")
                )
            } else if viewModel.filteredSummaries.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(sortedStudentIDs, id: \.self) { studentID in
                            if let studentSummaries = viewModel.summariesByStudent[studentID],
                               let firstName = studentSummaries.first?.studentName {
                                studentSection(name: firstName, studentID: studentID, summaries: studentSummaries)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Three-Period")
        .searchable(text: $viewModel.searchText, prompt: "Search lessons or students")
        .onAppear { viewModel.loadData(context: modelContext) }
    }

    private var sortedStudentIDs: [UUID] {
        viewModel.summariesByStudent.keys.sorted { lhs, rhs in
            let lhsName = viewModel.summariesByStudent[lhs]?.first?.studentName ?? ""
            let rhsName = viewModel.summariesByStudent[rhs]?.first?.studentName ?? ""
            return lhsName < rhsName
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Stage filter
                ForEach(ThreePeriodStage.allCases) { stage in
                    PillButton(
                        title: stage.shortName,
                        isSelected: viewModel.selectedStage == stage
                    ) {
                        viewModel.selectedStage = viewModel.selectedStage == stage ? nil : stage
                    }
                }

                Divider()
                    .frame(height: 20)

                // Student filter
                if !viewModel.availableStudents.isEmpty {
                    Menu {
                        Button("All Students") {
                            viewModel.selectedStudentID = nil
                        }
                        ForEach(viewModel.availableStudents, id: \.id) { student in
                            Button(student.name) {
                                viewModel.selectedStudentID = student.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person")
                                .font(.caption2)
                            Text(studentFilterLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(viewModel.selectedStudentID != nil ? Color.accentColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(viewModel.selectedStudentID != nil
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.secondary.opacity(0.1))
                        )
                    }
                }

                // Subject filter
                if !viewModel.availableSubjects.isEmpty {
                    Menu {
                        Button("All Subjects") {
                            viewModel.selectedSubject = nil
                        }
                        ForEach(viewModel.availableSubjects, id: \.self) { subject in
                            Button(subject) {
                                viewModel.selectedSubject = subject
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "book")
                                .font(.caption2)
                            Text(viewModel.selectedSubject ?? "Subject")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(viewModel.selectedSubject != nil ? Color.accentColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(viewModel.selectedSubject != nil
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.secondary.opacity(0.1))
                        )
                    }
                }
            }
        }
    }

    private var studentFilterLabel: String {
        if let id = viewModel.selectedStudentID,
           let student = viewModel.availableStudents.first(where: { $0.id == id }) {
            return student.name
        }
        return "Student"
    }

    // MARK: - Student Section

    private func studentSection(name: String, studentID: UUID, summaries: [ThreePeriodSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Student header with progress card
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
            }

            if let counts = viewModel.stageCountsByStudent[studentID] {
                ThreePeriodProgressCard(counts: counts)
            }

            // Lessons grouped by stage
            ForEach(ThreePeriodStage.allCases) { stage in
                let stageSummaries = summaries.filter { $0.stage == stage }
                if !stageSummaries.isEmpty {
                    stageGroup(stage: stage, summaries: stageSummaries)
                }
            }
        }
        .cardStyle()
    }

    private func stageGroup(stage: ThreePeriodStage, summaries: [ThreePeriodSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: stage.icon)
                    .foregroundStyle(stage.color)
                    .font(.caption)
                Text(stage.shortName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(stage.color)
                Text("\(summaries.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 4)

            ForEach(summaries) { summary in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.lessonName)
                            .font(.caption)
                            .fontWeight(.medium)
                        if !summary.lessonSubject.isEmpty {
                            Text(summary.lessonSubject)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if summary.presentationState != .proficient {
                        Button {
                            viewModel.advanceStage(presentationID: summary.id, context: modelContext)
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Advance to next period")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 2)
                .padding(.leading, 20)
            }
        }
    }
}
