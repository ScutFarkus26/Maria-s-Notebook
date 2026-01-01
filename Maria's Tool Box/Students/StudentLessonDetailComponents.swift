import SwiftUI

// MARK: - Student Chip Component
struct StudentChip: View {
    let student: Student
    let subjectColor: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(StudentFormatter.displayName(for: student))
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            
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
        .foregroundColor(subjectColor)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(subjectColor.opacity(0.15))
        )
    }
}

// MARK: - Student Selection Row
struct StudentSelectionRow: View {
    let student: Student
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
    let students: [Student]
    @Binding var studentsToMove: Set<UUID>
    let selectedStudentIDs: Set<UUID>
    let onMove: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Move Students to New Lesson")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Select students who didn't attend. They'll be moved to a new lesson with \"\(lessonName)\".")
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(students, id: \.id) { student in
                        MoveStudentRow(
                            student: student,
                            isSelected: studentsToMove.contains(student.id)
                        ) {
                            if studentsToMove.contains(student.id) {
                                studentsToMove.remove(student.id)
                            } else {
                                studentsToMove.insert(student.id)
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
                        Label("Move \(studentsToMove.count) Student\(studentsToMove.count == 1 ? "" : "s")", systemImage: "arrow.right.circle.fill")
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

// MARK: - Move Student Row
struct MoveStudentRow: View {
    let student: Student
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
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Banner Views
struct PlannedLessonBanner: View {
    var body: some View {
        Text("Next lesson added to Ready to Schedule")
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.95))
            )
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
            .padding(.top, 8)
    }
}

struct MovedStudentsBanner: View {
    let studentNames: [String]
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Students moved to new lesson")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            
            if !studentNames.isEmpty {
                Text(studentNames.joined(separator: ", "))
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.95))
        )
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        .padding(.top, 8)
    }
}

// MARK: - Utility for Student Name Formatting
enum StudentFormatter {
    static func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
}
