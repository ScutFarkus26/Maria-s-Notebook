import SwiftUI

struct StudentDetailHeaderView: View {
    let student: Student

    private var levelColor: Color {
        switch student.level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    private var initials: String {
        let parts = student.fullName.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let last = parts.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        } else if let first = student.fullName.first {
            return String(first).uppercased()
        } else {
            return "?"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.purple, Color.pink]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.pink.opacity(0.25), radius: 24, x: 0, y: 10)

                Text(initials)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))

            Text(student.level.rawValue)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(levelColor.opacity(0.12)))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    // Minimal placeholder preview
    let mock = Student(firstName: "Ava", lastName: "Lee", birthday: .now, level: .upper)
    StudentDetailHeaderView(student: mock)
}
