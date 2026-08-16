import SwiftUI
import CoreData

/// Collapsible section for deciding what happens with the next lesson after a presentation.
/// Used in both the split-panel workflow (iPad/macOS) and the compact sheet (iPhone).
struct NextLessonSection: View {
    @Bindable var viewModel: PostPresentationFormViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExpandableSectionButton(
                title: "Plan Next Lesson (Optional)",
                isExpanded: viewModel.isNextLessonSectionExpanded,
                action: {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.isNextLessonSectionExpanded.toggle()
                    }
                }
            )

            if viewModel.isNextLessonSectionExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let nextLesson = viewModel.nextLesson {
                        expandedContent(nextLesson: nextLesson)
                    } else {
                        noNextLessonContent
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        )
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(nextLesson: CDLesson) -> some View {
        // CDLesson name
        HStack(spacing: 8) {
            Image(systemName: SFSymbol.Education.bookFill)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(nextLesson.name)
                .font(AppTheme.ScaledFont.bodySemibold)
        }

        // Existing assignment status
        if let existing = viewModel.existingNextAssignment {
            existingAssignmentBadge(existing)
        }

        // Action picker
        actionPicker

        Text("Keep Watching leaves the next lesson unchanged. Nothing is planned unless you choose an option.")
            .font(AppTheme.ScaledFont.captionSmall)
            .foregroundStyle(.secondary)

        // Schedule date picker (only when scheduling)
        if viewModel.nextLessonAction == .schedule {
            DatePicker(
                "Schedule for",
                selection: $viewModel.nextLessonScheduleDate,
                in: Date()...,
                displayedComponents: .date
            )
            .font(AppTheme.ScaledFont.caption)
        }
    }

    // MARK: - Action Picker

    private var actionPicker: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) {
            ForEach(PostPresentationFormViewModel.NextLessonAction.allCases) { action in
                Button {
                    adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.nextLessonAction = action
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 11))
                        Text(action.rawValue)
                    }
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(pillForeground(for: action))
                    .background(
                        Capsule(style: .continuous)
                            .fill(pillBackground(for: action))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                pillBorder(for: action),
                                lineWidth: viewModel.nextLessonAction == action ? 1.5 : 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    viewModel.nextLessonAction == action ? .isSelected : []
                )
                .accessibilityValue(
                    viewModel.nextLessonAction == action ? "Selected" : "Not selected"
                )
            }
        }
    }

    // MARK: - Pill Styling

    private func pillColor(for action: PostPresentationFormViewModel.NextLessonAction) -> Color {
        switch action {
        case .noChange: return .gray
        case .inbox: return .blue
        case .schedule: return .green
        }
    }

    private func pillForeground(for action: PostPresentationFormViewModel.NextLessonAction) -> Color {
        return viewModel.nextLessonAction == action ? pillColor(for: action) : .secondary
    }

    private func pillBackground(for action: PostPresentationFormViewModel.NextLessonAction) -> Color {
        return viewModel.nextLessonAction == action
            ? pillColor(for: action).opacity(UIConstants.OpacityConstants.medium)
            : Color.primary.opacity(UIConstants.OpacityConstants.hint)
    }

    private func pillBorder(for action: PostPresentationFormViewModel.NextLessonAction) -> Color {
        return viewModel.nextLessonAction == action
            ? pillColor(for: action).opacity(UIConstants.OpacityConstants.muted)
            : Color.primary.opacity(UIConstants.OpacityConstants.accent)
    }

    // MARK: - No Next CDLesson

    private var noNextLessonContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.tertiary)
            Text("No next lesson in this sequence")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Existing Assignment Badge

    @ViewBuilder
    private func existingAssignmentBadge(_ assignment: CDLessonAssignment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))

            if let scheduledFor = assignment.scheduledFor {
                Text("Currently scheduled for \(scheduledFor.formatted(date: .abbreviated, time: .omitted))")
            } else {
                Text("Currently in inbox")
            }
        }
        .font(AppTheme.ScaledFont.captionSmall)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.blue.opacity(UIConstants.OpacityConstants.subtle))
        )
    }
}
