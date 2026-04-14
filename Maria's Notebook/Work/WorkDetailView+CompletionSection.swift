import SwiftUI
import CoreData
import Foundation

// MARK: - Completion & Presentation Sections

extension WorkDetailView {

    @ViewBuilder
    func completionSection() -> some View {
        DetailSectionCard(title: "Completion", icon: "checkmark.seal.fill", accentColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                // Outcome picker styled as pills
                Text("Outcome")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(CompletionOutcome.allCases, id: \.self) { outcome in
                        SelectablePillButton(
                            item: outcome,
                            isSelected: viewModel.completionOutcome == outcome,
                            color: outcome.color,
                            icon: outcome.iconName,
                            label: outcome.displayName
                        ) {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.completionOutcome = outcome
                            }
                        }
                    }
                }

                // Completion note
                TextField("Add a completion note...", text: $viewModel.completionNote)
                    .font(AppTheme.ScaledFont.body)
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
            }
        }
    }

    @ViewBuilder
    func stepsSection() -> some View {
        DetailSectionCard(
            title: "Steps",
            icon: "list.bullet.clipboard.fill",
            accentColor: .green,
            trailing: {
                Button { viewModel.showAddStepSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Add step")
                .buttonStyle(.plain)
            },
            content: {
                if let work = viewModel.work {
                    let orderedSteps = work.orderedSteps
                    if orderedSteps.isEmpty {
                        EmptyStateView(
                            icon: "checklist",
                            title: "No steps yet",
                            subtitle: "Add steps to track progress"
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(orderedSteps) { step in
                                WorkStepRow(step: step) {
                                    viewModel.stepBeingEdited = step
                                }
                            }
                        }
                    }

                    // Progress indicator
                    let progress = work.stepProgress
                    if progress.total > 0 {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(progress.completed), total: Double(progress.total))
                                .progressViewStyle(.linear)
                                .tint(.green)

                            Text("\(progress.completed)/\(progress.total)")
                                .font(AppTheme.ScaledFont.captionSemibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        )
    }

    @ViewBuilder
    var nextPresentationStatusSection: some View {
        if let status = presentationStatus, !status.isNotFound {
            presentationStatusCard(status: status)
        }
    }

    var presentationStatus: WorkPresentationStatusService.PresentationStatus? {
        guard let work = viewModel.work else { return nil }
        return WorkPresentationStatusService.findNextPresentationStatus(
            for: work,
            context: modelContext
        )
    }

    @ViewBuilder
    func presentationStatusCard(status: WorkPresentationStatusService.PresentationStatus) -> some View {

        DetailSectionCard(
            title: "Next Presentation",
            icon: status.iconName,
            accentColor: status.color
        ) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(UIConstants.OpacityConstants.light))
                        .frame(width: 44, height: 44)

                    Image(systemName: status.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(status.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.displayText)
                        .font(AppTheme.ScaledFont.bodySemibold)

                    // Additional context based on status
                    switch status {
                    case .scheduled(let date):
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    case .inInbox(let students):
                        if students.count > 1 {
                            Text("Ready to present with \(students.count) students")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Ready to present")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .withOtherStudents(let students):
                        let label = students.count == 1 ? "student" : "students"
                        Text("Waiting area with \(students.count) other \(label)")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    case .notFound:
                        EmptyView()
                    }
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .fill(status.color.opacity(UIConstants.OpacityConstants.veryFaint))
            )
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func presentationContextSection() -> some View {
        if let presentation = viewModel.relatedPresentation {
            DetailSectionCard(
                title: "From Presentation",
                icon: "calendar.badge.checkmark",
                accentColor: .indigo
            ) {
                VStack(spacing: 14) {
                    // Presentation date info
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(UIConstants.OpacityConstants.light))
                                .frame(width: 44, height: 44)

                            Image(systemName: presentation.isPresented ? "calendar.badge.checkmark" : "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.indigo)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            let statusText = presentation.isPresented
                                ? "Presented"
                                : presentation.isScheduled ? "Scheduled" : "Draft"
                            Text(statusText)
                                .font(AppTheme.ScaledFont.bodySemibold)

                            if let date = presentation.presentedAt ?? presentation.scheduledFor {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.indigo.opacity(UIConstants.OpacityConstants.veryFaint))
                    )

                    // Presentation flags
                    if presentation.needsPractice
                        || presentation.needsAnotherPresentation
                        || !presentation.followUpWork.isEmpty {
                        VStack(spacing: 8) {
                            if presentation.needsPractice {
                                FlagRow(icon: "arrow.counterclockwise", text: "Needs Practice", color: .orange)
                            }

                            if presentation.needsAnotherPresentation {
                                FlagRow(icon: "repeat", text: "Needs Re-presentation", color: .red)
                            }

                            if !presentation.followUpWork.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "list.clipboard")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Follow-up Work")
                                            .font(AppTheme.ScaledFont.captionSemibold)
                                    }
                                    .foregroundStyle(.blue)

                                    Text(presentation.followUpWork)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(AppTheme.Spacing.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                        .fill(Color.blue.opacity(UIConstants.OpacityConstants.faint))
                                )
                            }
                        }
                    }

                    // Presentation notes
                    if !presentation.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Presentation Notes")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(.purple)

                            Text(presentation.notes)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppTheme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.purple.opacity(UIConstants.OpacityConstants.faint))
                        )
                    }

                    // Students in presentation (if multiple)
                    let students = presentation.fetchStudents(from: modelContext)
                    if students.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Also presented to:")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                            }
                            .foregroundStyle(AppColors.success)

                            ForEach(students.filter { $0.id?.uuidString != viewModel.work?.studentID }) { student in
                                Text("\u{2022} \(StudentFormatter.displayName(for: student))")
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(AppTheme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.green.opacity(UIConstants.OpacityConstants.faint))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Peers Section

    @ViewBuilder
    func peersSection() -> some View {
        // Collaborators on this work item
        if !viewModel.workParticipants.isEmpty {
            DetailSectionCard(
                title: "Working With",
                icon: "person.2.fill",
                accentColor: .teal
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.workParticipants, id: \.student.objectID) { entry in
                        peerRow(
                            student: entry.student,
                            detail: participantDetail(completedAt: entry.completedAt)
                        )
                    }
                }
            }
        }

        // Lesson cohort (for progression work)
        if !viewModel.lessonCohort.isEmpty {
            DetailSectionCard(
                title: "Lesson Cohort",
                icon: "person.2.circle.fill",
                accentColor: .orange
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.lessonCohort, id: \.student.objectID) { entry in
                        cohortRow(entry)
                    }
                }
            }
        }

        // Awaiting follow-up (received lesson but no work yet)
        if !viewModel.awaitingFollowUp.isEmpty {
            DetailSectionCard(
                title: "Awaiting Follow-Up",
                icon: "bell.badge.fill",
                accentColor: .indigo
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.awaitingFollowUp) { student in
                        peerRow(
                            student: student,
                            detail: .badge("awaiting follow-up", color: .secondary)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Peer Row Helpers

    private enum PeerRowDetail {
        case none
        case badge(String, color: Color)
        case subtitle(String)
    }

    @ViewBuilder
    private func cohortRow(_ entry: LessonCohortEntry) -> some View {
        let detail: PeerRowDetail = {
            if entry.status == .complete {
                if let title = entry.currentWorkTitle {
                    return .subtitle("now on: \(title)")
                }
                return .badge("complete", color: .green)
            }
            if entry.status != viewModel.status {
                return .badge(entry.status.displayName.lowercased(), color: entry.status.color)
            }
            return .none
        }()

        peerRow(student: entry.student, detail: detail)
    }

    @ViewBuilder
    private func peerRow(student: CDStudent, detail: PeerRowDetail) -> some View {
        let hasPeerWork = student.id.flatMap { viewModel.peerWorkIDs[$0] } != nil

        HStack(spacing: 8) {
            Text(StudentFormatter.displayName(for: student))
                .font(AppTheme.ScaledFont.caption)

            switch detail {
            case .none:
                EmptyView()
            case .badge(let text, let color):
                Text(text)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(color.opacity(UIConstants.OpacityConstants.faint))
                    )
            case .subtitle(let text):
                Text(text)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasPeerWork {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let studentID = student.id,
               let workID = viewModel.peerWorkIDs[studentID] {
                selectedWorkID = workID
            }
        }
        .disabled(!hasPeerWork)
    }

    private func participantDetail(completedAt: Date?) -> PeerRowDetail {
        guard viewModel.status != .complete, completedAt != nil else { return .none }
        return .badge("completed", color: .green)
    }
}
