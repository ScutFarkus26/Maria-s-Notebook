import SwiftUI
import CoreData

// MARK: - Move Students Sheet
struct MoveStudentsSheet: View {
    /// The lesson the children get a plan for; nil until one is picked.
    let lessonName: String?
    let students: [CDStudent]
    @Binding var studentsToMove: Set<UUID>
    let selectedStudentIDs: Set<UUID>
    let onMove: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Split Off to a Different Group")
                    .font(AppTheme.ScaledFont.titleSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text(explanation)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
                
                // A whole-class presentation is taller than a phone: the list
                // scrolls so the footer's Split Off button stays in reach.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(students, id: \.objectID) { student in
                            let studentID = student.id ?? UUID()
                            MoveStudentRow(
                                student: student,
                                isSelected: studentsToMove.contains(studentID)
                            ) {
                                if studentsToMove.contains(studentID) {
                                    studentsToMove.remove(studentID)
                                } else {
                                    studentsToMove.insert(studentID)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)

            // Footer
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    
                    Spacer()
                    
                    Button {
                        onMove()
                    } label: {
                        Label(
                            "Split Off \(studentsToMove.count) \(studentsToMove.count == 1 ? "Child" : "Children")",
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lessonName == nil || studentsToMove.isEmpty || studentsToMove.count == selectedStudentIDs.count)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .frame(minWidth: 400, minHeight: 450)
    }

    private var explanation: String {
        guard let lessonName else {
            return "Pick this presentation's lesson first. The children you split off get a plan of their own for it."
        }
        return "Pick the children who should go to a different group. They'll leave this presentation and get a plan of their own for \"\(lessonName)\", ready to schedule. This happens straight away; an Undo shows at the top for a few seconds."
    }
}

// MARK: - Move CDStudent Row
struct MoveStudentRow: View {
    let student: CDStudent
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                    .font(.system(size: 20))
                
                Text(student.shortName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .surface(
                UIConstants.CornerRadius.medium,
                fill: isSelected ? Color.orange.opacity(UIConstants.OpacityConstants.light) : Color.clear,
                style: .continuous
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Split Banner

/// Says who was split off, with an Undo while the split can still be taken back.
struct SplitOffBanner: View {
    let names: [String]
    let onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text("Split off \(names.formatted(.list(type: .and))) into a group of their own.")
                .font(AppTheme.ScaledFont.captionSemibold)
            if let onUndo {
                Button("Undo", action: onUndo)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .underline()
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.orange.opacity(UIConstants.OpacityConstants.barelyTransparent),
            style: .continuous
        )
        .foregroundStyle(.white)
        .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }
}

