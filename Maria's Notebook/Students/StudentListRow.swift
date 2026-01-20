import SwiftUI
import SwiftData

/// A row component for displaying a student in a list view.
/// Shows the student's avatar (initials), name, and optional status badge based on sort mode.
/// Includes "fun" visuals matching the card designs: birthday cakes, age displays, and lesson status badges.
struct StudentListRow: View {
    let student: Student
    let sortOrder: SortOrder
    let daysSinceLastLesson: Int?
    
    @Environment(\.calendar) private var calendar
    
    private static let birthdayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt
    }()
    
    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
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
    
    // MARK: - Birthday Computations
    
    private var nextBirthdayDate: Date {
        let today = Date()
        let comps = calendar.dateComponents([.month, .day], from: student.birthday)
        let currentYear = calendar.component(.year, from: today)
        var thisYear = calendar.date(from: DateComponents(year: currentYear, month: comps.month, day: comps.day))
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYear == nil, comps.month == 2, comps.day == 29 {
            thisYear = calendar.date(from: DateComponents(year: currentYear, month: 2, day: 28))
        }
        guard let this = thisYear else { return today }
        let startOfToday = calendar.startOfDay(for: today)
        if this >= startOfToday { return this }
        let nextYear = currentYear + 1
        var next = calendar.date(from: DateComponents(year: nextYear, month: comps.month, day: comps.day))
        if next == nil, comps.month == 2, comps.day == 29 {
            next = calendar.date(from: DateComponents(year: nextYear, month: 2, day: 28))
        }
        return next ?? this
    }
    
    private var birthdayDateString: String {
        Self.birthdayFormatter.string(from: nextBirthdayDate)
    }
    
    // MARK: - Age Computations
    
    private var ageQuarter: (years: Int, months: Int) {
        AgeUtils.quarterRoundedAgeComponents(birthday: student.birthday)
    }
    
    private var ageDisplayString: String {
        let y = ageQuarter.years
        let m = ageQuarter.months
        switch m {
        case 0: return "\(y)"
        case 3: return "\(y) 1/4"
        case 6: return "\(y) 1/2"
        case 9: return "\(y) 3/4"
        default: return "\(y)"
        }
    }
    
    // MARK: - Trailing Badge/Status
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [levelColor.opacity(0.8), levelColor]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Text(initials)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Name only
            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    let container = ModelContainer.preview
    let student = Student(
        firstName: "John",
        lastName: "Doe",
        birthday: Date(),
        level: .upper
    )
    
    List {
        StudentListRow(student: student, sortOrder: .alphabetical, daysSinceLastLesson: nil)
        StudentListRow(student: student, sortOrder: .birthday, daysSinceLastLesson: nil)
        StudentListRow(student: student, sortOrder: .age, daysSinceLastLesson: nil)
    }
    .modelContainer(container)
}
