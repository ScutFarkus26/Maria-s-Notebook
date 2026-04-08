// SmallGroupPlannerLessonDetail.swift
// Per-lesson drill-down showing three collapsible readiness tiers with student selection.

import SwiftUI
import CoreData

struct SmallGroupPlannerLessonDetail: View {
    let candidate: LessonGroupCandidate
    @Bindable var viewModel: SmallGroupPlannerViewModel
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isReadyExpanded = true
    @State private var isAlmostReadyExpanded = true
    @State private var isNotReadyExpanded = false
    @State private var showPresentationConfirmation = false

    private var selectedCount: Int {
        viewModel.selectedStudentIDs.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                headerCard

                // Almost-ready banner
                if !candidate.almostReadyStudents.isEmpty {
                    catchUpBanner
                }

                // Ready section
                readySection

                // Almost Ready section
                almostReadySection

                // Not Ready section
                notReadySection
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 100) // Space for bottom bar
        }
        .overlay(alignment: .bottom) {
            if selectedCount > 0 {
                bottomBar
            }
        }
        .navigationTitle(candidate.lessonName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onDisappear {
            viewModel.selectedStudentIDs.removeAll()
        }
        .alert("Create Presentation",
               isPresented: $showPresentationConfirmation) {
            Button("Create") {
                viewModel.createPresentation(lessonID: candidate.id, context: viewContext)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Create a presentation of \(candidate.lessonName) for \(selectedCount) student\(selectedCount == 1 ? "" : "s")?")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(candidate.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Order badge
                Text("#\(candidate.orderInGroup)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.gradient)
                    )
            }

            if let preceding = candidate.precedingLessonName {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.caption2)
                    Text("After: \(preceding)")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }

            // Stats row
            HStack(spacing: 16) {
                statBadge(count: candidate.readyCount, label: "Ready", color: AppColors.success)
                statBadge(count: candidate.almostReadyCount, label: "Almost", color: AppColors.warning)
                statBadge(count: candidate.notReadyCount, label: "Not Ready", color: .secondary)
            }
        }
        .cardStyle()
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Catch-Up Banner

    private var catchUpBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(AppColors.warning)
            Text("\(candidate.almostReadyCount) student\(candidate.almostReadyCount == 1 ? "" : "s") could join with catch-up")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.hint))
        )
    }

    // MARK: - Ready Section

    private var readySection: some View {
        tierSection(
            title: "Ready",
            icon: SFSymbol.Action.checkmarkCircleFill,
            color: AppColors.success,
            count: candidate.readyCount,
            isExpanded: $isReadyExpanded
        ) {
            if !candidate.readyStudents.isEmpty {
                selectAllButton(for: candidate)
            }

            ForEach(candidate.readyStudents) { student in
                SmallGroupPlannerStudentRow(
                    student: student,
                    isSelected: viewModel.selectedStudentIDs.contains(student.id),
                    onToggle: { viewModel.toggleStudentSelection(student.id) }
                )
            }
        }
    }

    // MARK: - Almost Ready Section

    private var almostReadySection: some View {
        tierSection(
            title: "Almost Ready",
            icon: "clock.badge.exclamationmark",
            color: AppColors.warning,
            count: candidate.almostReadyCount,
            isExpanded: $isAlmostReadyExpanded
        ) {
            ForEach(candidate.almostReadyStudents) { student in
                SmallGroupPlannerStudentRow(
                    student: student,
                    isSelected: viewModel.selectedStudentIDs.contains(student.id),
                    onToggle: { viewModel.toggleStudentSelection(student.id) },
                    onConfirmMastery: { assignmentID in
                        viewModel.confirmMastery(
                            studentID: student.id,
                            assignmentID: assignmentID,
                            context: viewContext
                        )
                    }
                )
            }
        }
    }

    // MARK: - Not Ready Section

    private var notReadySection: some View {
        Group {
            if candidate.notReadyCount > 0 {
                tierSection(
                    title: "Not Ready",
                    icon: "minus.circle",
                    color: .secondary,
                    count: candidate.notReadyCount,
                    isExpanded: $isNotReadyExpanded
                ) {
                    Text("\(candidate.notReadyCount) students are 2+ lessons behind in this sequence.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Tier Section Template

    private func tierSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(color.gradient)
                        )

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(spacing: 0) {
                    content()
                }
                .padding(.leading, 4)
            }
        }
        .cardStyle()
    }

    // MARK: - Select All Button

    private func selectAllButton(for candidate: LessonGroupCandidate) -> some View {
        Button {
            viewModel.selectAllReady(for: candidate)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Select All Ready")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(AppColors.success)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text("\(selectedCount) student\(selectedCount == 1 ? "" : "s") selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showPresentationConfirmation = true
                } label: {
                    Label("Create Presentation", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}
