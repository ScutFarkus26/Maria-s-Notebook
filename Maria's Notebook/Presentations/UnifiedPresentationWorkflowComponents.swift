import SwiftUI

// MARK: - Section Header

struct WorkflowSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Understanding Level Components

struct UnderstandingLevelRow: View {
    @Binding var selectedLevel: Int
    let showLabel: Bool

    init(selectedLevel: Binding<Int>, showLabel: Bool = true) {
        self._selectedLevel = selectedLevel
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    selectedLevel = level
                } label: {
                    Circle()
                        .fill(UnderstandingLevel.color(for: level).opacity(
                            selectedLevel >= level ? 1.0 : 0.2
                        ))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            if showLabel {
                Spacer()
                Text(UnderstandingLevel.label(for: selectedLevel))
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CompactUnderstandingIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(UnderstandingLevel.color(for: level).opacity(i <= level ? 1.0 : 0.2))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct MiniUnderstandingIndicator: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(UnderstandingLevel.color(for: level).opacity(i <= level ? 1.0 : 0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Date Picker with Toggle

struct WorkflowDatePicker: View {
    let label: String
    @Binding var date: Date?
    let defaultDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Button {
                    if date != nil {
                        date = nil
                    } else {
                        date = defaultDate
                    }
                } label: {
                    Image(systemName: date != nil ? "checkmark.square.fill" : "square")
                        .foregroundStyle(date != nil ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                if date != nil {
                    DatePicker("", selection: Binding(
                        get: { date ?? defaultDate },
                        set: { date = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                }
            }
        }
    }
}

// MARK: - Styled Text Fields

struct WorkflowTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var axis: Axis = .horizontal
    var lineLimit: PartialRangeFrom<Int>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Group {
                if let lineLimit = lineLimit {
                    TextField(placeholder, text: $text, axis: axis)
                        .lineLimit(lineLimit)
                } else {
                    TextField(placeholder, text: $text, axis: axis)
                }
            }
            .font(.system(size: AppTheme.FontSize.body, weight: axis == .horizontal ? .medium : .regular, design: .rounded))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: axis == .horizontal ? 12 : 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: axis == .horizontal ? 12 : 10)
                    .stroke(Color.primary.opacity(axis == .horizontal ? 0.08 : 0), lineWidth: 1)
            )
        }
    }
}

// MARK: - Card Container

struct WorkflowCard<Content: View>: View {
    let content: Content
    var backgroundColor: Color = Color.primary.opacity(0.04)
    var borderColor: Color = Color.primary.opacity(0.1)
    var cornerRadius: CGFloat = 12

    init(
        backgroundColor: Color = Color.primary.opacity(0.04),
        borderColor: Color = Color.primary.opacity(0.1),
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Status Button (Generic)

struct WorkflowStatusButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(color)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(isSelected ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(isSelected ? 0.5 : 0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable Section Header

struct ExpandableSectionButton: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Delete Button

struct WorkflowDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                Text("Remove")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Hint

struct WorkflowInfoHint: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Badge View

struct WorkflowBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
}

// MARK: - Panel Header

struct WorkflowPanelHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.bar)
    }
}

// MARK: - Student Entry Row Header

struct StudentEntryRowHeader: View {
    let studentName: String
    let hasContent: Bool
    let isExpanded: Bool
    let understandingLevel: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(studentName)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            CompactUnderstandingIndicator(level: understandingLevel)

            HStack(spacing: 4) {
                if hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
                .fill(Color.primary.opacity(isExpanded ? 0.06 : 0.03))
        )
        .contentShape(Rectangle())
    }
}


// MARK: - Date Picker Row

struct WorkDatesRow: View {
    @Binding var checkInDate: Date?
    @Binding var dueDate: Date?
    let defaultCheckInDate: Date
    let defaultDueDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dates")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                WorkflowDatePicker(
                    label: "Check-in",
                    date: $checkInDate,
                    defaultDate: defaultCheckInDate
                )

                WorkflowDatePicker(
                    label: "Due Date",
                    date: $dueDate,
                    defaultDate: defaultDueDate
                )

                Spacer()
            }
        }
    }
}

