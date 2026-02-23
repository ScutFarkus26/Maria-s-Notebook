import SwiftUI

/// A reusable student avatar view with initials and color
struct StudentAvatarView: View {
    let student: Student
    let size: CGFloat
    
    init(student: Student, size: CGFloat = UIConstants.CardSize.studentAvatar) {
        self.student = student
        self.size = size
    }
    
    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(levelColor.opacity(UIConstants.OpacityConstants.medium))
            
            Text(student.initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(levelColor)
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
// Note: Preview requires a Student model instance
// Use in views that already have access to students
#endif
