import SwiftUI

/// Collapsible section for deciding what happens with the next lesson after a presentation.
/// Used in both the split-panel workflow (iPad/macOS) and the compact sheet (iPhone).
struct NextLessonSection: View {
    @Bindable var viewModel: PostPresentationFormViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExpandableSectionButton(
                title: "Next Lesson",
                isExpanded: viewModel.isNextLessonSectionExpanded,
                action: {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.isNextLessonSectionExpanded.toggle()
                    }
                }
            )
            .onChange(of: viewModel.isHoldEnabled) { _, holdEnabled in
                if !holdEnabled && viewModel.nextLessonAction == .hold {
                    viewModel.nextLessonAction = .inbox
                }
            }

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
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(nextLesson: Lesson) -> some View {
        // Lesson name
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

        // Hold disabled hint
        if !viewModel.isHoldEnabled {
            Text("Assign work to enable hold")
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.tertiary)
        }

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
        HStack(spacing: 8) {
            ForEach(PostPresentationFormViewModel.NextLessonAction.allCases) { action in
                let isDisabled = action == .hold && !viewModel.isHoldEnabled
                Button {
                    guard !isDisabled else { return }
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
                    .foregroundStyle(pillForeground(for: action, isDisabled: isDisabled))
                    .background(
                        Capsule(style: .continuous)
                            .fill(pillBackground(for: action, isDisabled: isDisabled))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                pillBorder(for: action, isDisabled: isDisabled),
                                lineWidth: viewModel.nextLessonAction == action ? 1.5 : 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .opacity(isDisabled ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Pill Styling

    private func pillColor(for action: PostPresentationFormViewModel.NextLessonAction) -> Color {
        switch action {
        case .hold: return .orange
        case .inbox: return .blue
        case .schedule: return .green
        }
    }

    private func pillForeground(
        for action: PostPresentationFormViewModel.NextLessonAction,
        isDisabled: Bool
    ) -> Color {
        if isDisabled { return .secondary }
        return viewModel.nextLessonAction == action ? pillColor(for: action) : .secondary
    }

    private func pillBackground(
        for action: PostPresentationFormViewModel.NextLessonAction,
        isDisabled: Bool
    ) -> Color {
        if isDisabled { return Color.primary.opacity(0.03) }
        return viewModel.nextLessonAction == action
            ? pillColor(for: action).opacity(0.12)
            : Color.primary.opacity(0.05)
    }

    private func pillBorder(
        for action: PostPresentationFormViewModel.NextLessonAction,
        isDisabled: Bool
    ) -> Color {
        if isDisabled { return Color.primary.opacity(0.1) }
        return viewModel.nextLessonAction == action
            ? pillColor(for: action).opacity(0.4)
            : Color.primary.opacity(0.15)
    }

    // MARK: - No Next Lesson

    private var noNextLessonContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.tertiary)
            Text("No next lesson in this group")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Existing Assignment Badge

    @ViewBuilder
    private func existingAssignmentBadge(_ assignment: LessonAssignment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))

            if assignment.scheduledFor != nil {
                Text("Currently scheduled for \(assignment.scheduledFor!.formatted(date: .abbreviated, time: .omitted))")
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
                .fill(Color.blue.opacity(0.08))
        )
    }
}
