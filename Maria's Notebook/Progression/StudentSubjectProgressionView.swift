// StudentSubjectProgressionView.swift
// Single student's full timeline through a subject/group.

import SwiftUI
import SwiftData

/// Shows one student's full lesson timeline through a subject/group.
struct StudentSubjectProgressionView: View {
    let student: Student
    let subject: String
    let group: String

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StudentSubjectProgressionViewModel()

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.nodes.isEmpty {
                ContentUnavailableView {
                    Label("No Lessons", systemImage: SFSymbol.Education.book)
                } description: {
                    Text("No lessons found in \(subject) > \(group).")
                }
            } else {
                scrollContent
            }
        }
        .navigationTitle(student.fullName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            viewModel.configure(for: student, subject: subject, group: group, context: modelContext)
        }
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header card
                headerCard

                // Lesson timeline
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.nodes) { node in
                        ProgressionLessonRow(
                            node: node,
                            subjectColor: subjectColor,
                            onScheduleLesson: node.isNext ? {
                                scheduleNextLesson(after: node)
                            } : nil
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 12) {
            // Subject color bar
            RoundedRectangle(cornerRadius: 3)
                .fill(subjectColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(subject) > \(group)")
                    .font(.headline)
                Text(student.fullName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress counter
            Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                .font(.title2.bold())
                .foregroundStyle(subjectColor)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
        .padding()
    }

    // MARK: - Actions

    private func scheduleNextLesson(after node: LessonProgressionNode) {
        viewModel.scheduleNextLesson(after: node.lesson, context: modelContext)
        viewModel.configure(for: student, subject: subject, group: group, context: modelContext)
    }
}
