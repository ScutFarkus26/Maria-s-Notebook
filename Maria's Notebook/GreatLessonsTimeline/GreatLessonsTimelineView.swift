// GreatLessonsTimelineView.swift
// Root view for the Five Great Lessons Timeline feature.
// Shows cosmic education themes with per-student lesson progress mapped to each.

import SwiftUI
import CoreData

struct GreatLessonsTimelineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = GreatLessonsTimelineViewModel()
    @State private var scope: AnalyticsScope = .classroom
    @State private var selectedStudentID: UUID?

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)]
    ) private var assignmentsForChange: FetchedResults<CDLessonAssignment>

    private var changeToken: Int { assignmentsForChange.count }

    // Student list for picker
    @FetchRequest(
        sortDescriptors: CDStudent.sortByName,
        predicate: NSPredicate(format: "enrollmentStatusRaw == %@", CDStudent.EnrollmentStatus.enrolled.rawValue)
    ) private var students: FetchedResults<CDStudent>

    private var visibleStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(Array(students))
    }

    var body: some View {
        content
            .navigationTitle("Great Lessons")
            .searchable(text: $viewModel.searchText, prompt: "Search lessons or subjects")
            .onAppear { reload() }
            .onChange(of: changeToken) { _, _ in reload() }
            .onChange(of: scope) { _, _ in reload() }
            .onChange(of: selectedStudentID) { _, _ in reload() }
    }

    private func reload() {
        viewModel.selectedStudentID = scope == .perStudent ? selectedStudentID : nil
        viewModel.loadData(context: viewContext)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.branches.allSatisfy({ $0.totalLessons == 0 }) {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Scope toggle
                scopeToggle
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Student picker (when per-student)
                if scope == .perStudent {
                    studentPicker
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Summary row
                summaryRow
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                // Branch cards
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.filteredBranches) { branch in
                        NavigationLink(value: branch.greatLesson) {
                            GreatLessonBranchCard(branch: branch)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Unmapped lessons banner
                if viewModel.unmappedLessonCount > 0 {
                    unmappedBanner
                        .padding(.horizontal)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationDestination(for: GreatLesson.self) { gl in
            if let branch = viewModel.branches.first(where: { $0.greatLesson == gl }) {
                GreatLessonStudentProgressView(branch: branch)
            }
        }
    }

    // MARK: - Scope Toggle

    private var scopeToggle: some View {
        Picker("Scope", selection: $scope) {
            ForEach(AnalyticsScope.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Student Picker

    private var studentPicker: some View {
        Picker("Student", selection: $selectedStudentID) {
            Text("All Students").tag(UUID?.none)
            ForEach(visibleStudents) { student in
                Text(StudentFormatter.displayName(for: student))
                    .tag(Optional(student.id))
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let totalLessons = viewModel.branches.reduce(0) { $0 + $1.totalLessons }
        let branchesWithData = viewModel.branches.filter { $0.totalLessons > 0 }.count

        return HStack(spacing: 0) {
            Text("\(totalLessons)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" lessons across ")
                .foregroundStyle(.tertiary)
            Text("\(branchesWithData)/5")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" Great Lessons")
                .foregroundStyle(.tertiary)
            if viewModel.unmappedLessonCount > 0 {
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.unmappedLessonCount) unmapped")
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.warning)
            }
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Unmapped Banner

    private var unmappedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.slash")
                .foregroundStyle(AppColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.unmappedLessonCount) lessons not connected to a Great Lesson")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Tag them in the Lesson detail view to see them here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lessons", systemImage: "sparkles")
        } description: {
            Text("Add lessons to your curriculum to see how they connect to the Five Great Lessons of cosmic education.")
        }
    }
}
