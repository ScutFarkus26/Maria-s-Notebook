import SwiftUI

struct StudentPillsSection: View {
    let students: [Student]
    let subjectColor: Color
    var onRemove: (UUID) -> Void
    var onOpenPicker: () -> Void
    var onOpenMove: () -> Void
    let canMoveStudents: Bool
    var onOpenMoveAbsent: () -> Void
    let canMoveAbsentStudents: Bool

    var body: some View {
        VStack(spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(students, id: \.id) { student in
                    studentChip(for: student)
                }
            }

            HStack(spacing: 12) {
                Button(action: onOpenPicker) {
                    Label("Add/Remove Students", systemImage: "person.2.badge.gearshape")
                        .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                }
                .buttonStyle(.bordered)

                if canMoveStudents {
                    Button(action: onOpenMove) {
                        Label("Move Students", systemImage: "arrow.right.square")
                            .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                }

                if canMoveAbsentStudents {
                    Button(action: onOpenMoveAbsent) {
                        Label("Move Absent Students", systemImage: "person.fill.xmark")
                            .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func studentChip(for student: Student) -> some View {
        HStack(spacing: 6) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            Button { onRemove(student.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(subjectColor)
            .accessibilityLabel("Remove \(StudentFormatter.displayName(for: student))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(subjectColor)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(subjectColor.opacity(0.15))
        )
    }
}

