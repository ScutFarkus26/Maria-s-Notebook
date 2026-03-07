import SwiftUI
import SwiftData
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
            modelContext: modelContext
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

                            ForEach(students.filter { $0.id.uuidString != viewModel.work?.studentID }) { student in
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
}
