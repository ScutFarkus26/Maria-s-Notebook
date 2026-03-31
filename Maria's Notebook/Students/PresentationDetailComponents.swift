import SwiftUI
import CoreData

// MARK: - CDStudent Chip Component
struct StudentChip: View {
    let student: CDStudent
    let subjectColor: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(StudentFormatter.displayName(for: student))
                .font(AppTheme.ScaledFont.captionSemibold)
            
            Button {
                onRemove()
            } label: {
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
                .fill(subjectColor.opacity(UIConstants.OpacityConstants.accent))
        )
    }
}

// MARK: - CDStudent Selection Row
struct StudentSelectionRow: View {
    let student: CDStudent
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                
                Text(StudentFormatter.displayName(for: student))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }
}

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
                            "Move \(studentsToMove.count) Student\(studentsToMove.count == 1 ? "" : "s")",
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
                
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(UIConstants.OpacityConstants.light) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Banner Views
struct PlannedLessonBanner: View {
    var body: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(UIConstants.OpacityConstants.barelyTransparent))
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}

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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(UIConstants.OpacityConstants.barelyTransparent))
        )
        .foregroundStyle(.white)
        .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
        .padding(.top, 8)
    }
}

// MARK: - Utility for CDStudent Name Formatting

/// Consistent student name formatting used across the app.
enum StudentFormatter {
    /// Returns "FirstName L." format (e.g. "Maria D.")
    static func displayName(for student: CDStudent) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    /// Returns just the first name
    static func firstName(for student: CDStudent) -> String {
        let parts = student.fullName.split(separator: " ")
        return parts.first.map(String.init) ?? student.fullName
    }
}
