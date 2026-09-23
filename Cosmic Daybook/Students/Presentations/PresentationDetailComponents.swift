import SwiftUI
import CoreData

// MARK: - Move Students Sheet
struct MoveStudentsSheet: View {
    let lessonName: String
    let students: [CDStudent]
    @Binding var studentsToMove: Set<UUID>
    let selectedStudentIDs: Set<UUID>
    let onMove: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Move Students to New Lesson")
                    .font(AppTheme.ScaledFont.titleSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Select students who didn't attend. They'll be moved to a new lesson with \"\(lessonName)\".")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
                
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
            .padding(24)
            
            Spacer()
            
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
                            "Move \(studentsToMove.count) student\(studentsToMove.count == 1 ? "" : "s")",
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(studentsToMove.isEmpty || studentsToMove.count == selectedStudentIDs.count)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .frame(minWidth: 400, minHeight: 450)
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

// MARK: - Banner Views

struct MovedStudentsBanner: View {
    let studentNames: [String]
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Students moved to new lesson")
                .font(AppTheme.ScaledFont.captionSemibold)
            
            if !studentNames.isEmpty {
                Text(studentNames.joined(separator: ", "))
                    .font(AppTheme.ScaledFont.captionSmall)
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
    }
}
