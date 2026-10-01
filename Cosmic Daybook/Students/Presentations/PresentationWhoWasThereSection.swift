import SwiftUI

/// "Who was there?": one tile per child on the plan, ticked from the day's
/// attendance. A child left unticked keeps her place on the plan when the
/// presentation is recorded for the others.
struct PresentationWhoWasThereSection<AddButton: View>: View {
    let students: [CDStudent]
    let presentIDs: Set<UUID>
    let attendance: [UUID: AttendanceStatus]
    let isToday: Bool
    let onToggle: (UUID) -> Void
    let onRemove: (UUID) -> Void
    @ViewBuilder let addButton: AddButton

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Who was there?")
                    .font(AppTheme.ScaledFont.titleSmall)
                Text(isToday
                     ? "From today's attendance. Tap a child to change it."
                     : "From that day's attendance. Tap a child to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(students) { student in
                    tile(student)
                }
            }

            addButton
        }
    }

    private func tile(_ student: CDStudent) -> some View {
        let id = student.id ?? UUID()
        let isPresent = presentIDs.contains(id)
        let status = attendance[id] ?? .unmarked
        return Button {
            onToggle(id)
        } label: {
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 36)
                    .opacity(isPresent ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.shortName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)
                    Text(statusText(isPresent: isPresent, status: status))
                        .font(.caption)
                        .foregroundStyle(isPresent ? AppColors.success : PresentationDecisionChip.differsColor)
                }
                Spacer(minLength: 4)
                Image(systemName: isPresent ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPresent ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                    .fill(isPresent ? Color.accentColor.opacity(UIConstants.OpacityConstants.subtle) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        isPresent ? Color.accentColor : Color.secondary.opacity(UIConstants.OpacityConstants.semi),
                        style: StrokeStyle(lineWidth: 1.5, dash: isPresent ? [] : [5, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(student.shortName)
        .accessibilityValue(isPresent ? "Was there" : "Not there, stays on the plan")
        .accessibilityAddTraits(isPresent ? .isSelected : [])
        .contextMenu {
            Button("Remove from This Presentation", systemImage: "person.badge.minus", role: .destructive) {
                onRemove(id)
            }
        }
    }

    private func statusText(isPresent: Bool, status: AttendanceStatus) -> String {
        switch (isPresent, status) {
        case (true, .absent): "Marked absent, but here"
        case (true, .tardy): "Here (late)"
        case (true, .present): "Here"
        case (true, _): "Was there"
        case (false, .absent): "Absent · stays on the plan"
        case (false, _): "Not there · stays on the plan"
        }
    }
}
