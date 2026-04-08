// SmallGroupPlannerView.swift
// Root view for Small Group Planning Intelligence — subject/group pickers with lesson card list.

import SwiftUI
import CoreData

struct SmallGroupPlannerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = SmallGroupPlannerViewModel()

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)],
        predicate: NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
    ) private var presentedAssignments: FetchedResults<CDLessonAssignment>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.id, ascending: true)]
    ) private var allWork: FetchedResults<CDWorkModel>

    private var changeToken: Int { presentedAssignments.count + allWork.count }

    var body: some View {
        content
            .navigationTitle("Group Planner")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in viewModel.loadData(context: viewContext) }
            .onChange(of: viewModel.selectedSubject) { _, _ in
                viewModel.selectedGroup = viewModel.availableGroups.first
                viewModel.loadData(context: viewContext)
            }
            .onChange(of: viewModel.selectedGroup) { _, _ in
                viewModel.loadData(context: viewContext)
            }
            .onChange(of: viewModel.levelFilter) { _, _ in
                viewModel.loadData(context: viewContext)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.subjects.isEmpty {
            emptyStateNoLessons
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Pickers
                pickerBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Level filter
                levelFilter
                    .padding(.horizontal)

                // Summary
                if viewModel.selectedSubject != nil && viewModel.selectedGroup != nil {
                    summaryRow
                        .padding(.horizontal)
                }

                // Lesson cards
                if viewModel.filteredCandidates.isEmpty && viewModel.selectedGroup != nil {
                    emptyStateNoOpportunities
                } else {
                    lessonCards
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Picker Bar

    private var pickerBar: some View {
        VStack(spacing: 10) {
            // Subject picker
            HStack {
                Text("Subject")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Subject", selection: $viewModel.selectedSubject) {
                    Text("Select…").tag(nil as String?)
                    ForEach(viewModel.subjects, id: \.self) { subject in
                        Text(subject).tag(subject as String?)
                    }
                }
                .pickerStyle(.menu)
            }

            // Group picker
            if viewModel.selectedSubject != nil {
                HStack {
                    Text("Group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Group", selection: $viewModel.selectedGroup) {
                        Text("Select…").tag(nil as String?)
                        ForEach(viewModel.availableGroups, id: \.self) { group in
                            Text(group).tag(group as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Level Filter

    private var levelFilter: some View {
        Picker("Level", selection: $viewModel.levelFilter) {
            ForEach(LevelFilter.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 0) {
            let count = viewModel.filteredCandidates.count
            Text("\(count)")
                .fontWeight(.semibold)
            Text(" lesson\(count == 1 ? "" : "s") with group opportunities")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Lesson Cards

    private var lessonCards: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredCandidates) { candidate in
                NavigationLink(value: candidate.id) {
                    lessonCard(candidate)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: UUID.self) { lessonID in
            if let candidate = viewModel.filteredCandidates.first(where: { $0.id == lessonID }) {
                SmallGroupPlannerLessonDetail(
                    candidate: candidate,
                    viewModel: viewModel
                )
            }
        }
    }

    private func lessonCard(_ candidate: LessonGroupCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 8) {
                // Order badge
                Text("\(candidate.orderInGroup)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.accentColor.gradient)
                    )

                Text(candidate.lessonName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }

            // Preceding lesson
            if let preceding = candidate.precedingLessonName {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 8))
                    Text("After: \(preceding)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }

            // Readiness badges
            HStack(spacing: 8) {
                readinessBadge(
                    count: candidate.readyCount,
                    icon: SFSymbol.Action.checkmarkCircleFill,
                    label: "Ready",
                    color: AppColors.success
                )

                if candidate.almostReadyCount > 0 {
                    readinessBadge(
                        count: candidate.almostReadyCount,
                        icon: "clock.badge.exclamationmark",
                        label: "Almost",
                        color: AppColors.warning
                    )
                }

                Spacer()

                // Student initials preview
                initialsPreview(candidate.readyStudents.prefix(4))
            }
        }
        .cardStyle()
    }

    private func readinessBadge(count: Int, icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(count) \(label)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(UIConstants.OpacityConstants.light))
        )
    }

    private func initialsPreview(_ students: ArraySlice<GroupStudentStatus>) -> some View {
        HStack(spacing: -6) {
            ForEach(Array(students)) { student in
                Text(student.initials)
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        AppColors.color(forLevel: student.level).gradient,
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(.background, lineWidth: 1.5)
                    )
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateNoLessons: some View {
        ContentUnavailableView {
            Label("No Lessons", systemImage: "person.3.sequence")
        } description: {
            Text("Add lessons with subjects and groups to find group presentation opportunities.")
        }
    }

    private var emptyStateNoOpportunities: some View {
        ContentUnavailableView {
            Label("No Group Opportunities", systemImage: "person.3.sequence")
        } description: {
            Text("No students are ready or almost ready for lessons in this group. Try a different subject or group.")
        }
        .padding(.top, 40)
    }
}
