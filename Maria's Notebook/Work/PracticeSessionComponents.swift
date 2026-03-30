import SwiftUI

// MARK: - Rating Level Selector

struct RatingLevelSelector: View {
    let label: String
    @Binding var selectedLevel: Int?
    let color: Color
    let levelLabels: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        selectedLevel = (selectedLevel == level) ? nil : level
                    } label: {
                        Circle()
                            .fill(color.opacity(selectedLevel == level ? 1.0 : 0.2))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("\(level)")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(selectedLevel == level ? .white : color)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let level = selectedLevel {
                    Text(levelLabels(level))
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Student Understanding Selector

struct StudentUnderstandingSelector: View {
    @Binding var level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Understanding")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        level = index
                    } label: {
                        Circle()
                            .fill(understandingColor(for: index).opacity(level >= index ? 1.0 : 0.2))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(understandingLabel(for: level))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func understandingColor(for level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .blue
        default: return .gray
        }
    }

    private func understandingLabel(for level: Int) -> String {
        switch level {
        case 1: return "Struggling"
        case 2: return "Needs Support"
        case 3: return "Developing"
        case 4: return "Proficient"
        case 5: return "Mastered"
        default: return ""
        }
    }
}

// MARK: - Section Header

struct PracticeSectionHeader: View {
    let title: String
    let icon: String?
    let color: Color?

    init(title: String, icon: String? = nil, color: Color? = nil) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon, let color = color {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16))
            }
            Text(title)
                .font(AppTheme.ScaledFont.calloutSemibold)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Styled Multi-line Text Field

struct StyledNotesTextField: View {
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 3...8

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(AppTheme.ScaledFont.body)
            .lineLimit(lineLimit)
            .textFieldStyle(.plain)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: 1)
            )
    }
}

// MARK: - Optional Field Toggle Section

struct OptionalFieldToggle<Content: View>: View {
    let title: String
    @Binding var isEnabled: Bool
    let content: () -> Content

    init(title: String, isEnabled: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isEnabled = isEnabled
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEnabled) {
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
            }

            if isEnabled {
                content()
                    .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Selected Student Row

struct SelectedStudentRow: View {
    let student: Student
    let workTitle: String?
    let showRemoveButton: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.bodySemibold)

                if let title = workTitle {
                    Text(title)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if showRemoveButton {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(UIConstants.OpacityConstants.light))
        )
    }
}

// MARK: - Student Selector Search Bar

struct StudentSelectorSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search students...", text: $searchText)
                .font(AppTheme.ScaledFont.body)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
    }
}

// MARK: - Lesson Context Card

struct LessonContextCard: View {
    let lesson: Lesson
    let presentation: Presentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.indigo)
                    .font(.system(size: 16))
                Text("Lesson Context")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Lesson info
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.name)
                            .font(AppTheme.ScaledFont.bodySemibold)

                        if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                            HStack(spacing: 6) {
                                if !lesson.subject.isEmpty {
                                    Text(lesson.subject)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if !lesson.subject.isEmpty && !lesson.group.isEmpty {
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                }

                                if !lesson.group.isEmpty {
                                    Text(lesson.group)
                                        .font(AppTheme.ScaledFont.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.indigo.opacity(UIConstants.OpacityConstants.subtle))
                )

                // Presentation info if available
                if let presentation {
                    HStack(spacing: 8) {
                        Image(systemName: presentation.isPresented ? "calendar.badge.checkmark" : "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(.indigo)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.isPresented ? "Presented" : "Scheduled")
                                .font(AppTheme.ScaledFont.captionSemibold)

                            if let date = presentation.presentedAt ?? presentation.scheduledFor {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppTheme.ScaledFont.captionSmall)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.indigo.opacity(0.05))
                    )
                }
            }
        }
    }
}

// MARK: - Bottom Action Bar

struct PracticeSessionBottomBar: View {
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onSave) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSave ? Color.accentColor : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(16)
    }
}
