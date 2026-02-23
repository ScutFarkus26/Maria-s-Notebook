import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A row component for displaying a student in a list view.
/// Shows the student's avatar (initials), name, and optional status badge based on sort mode.
/// Includes "fun" visuals matching the card designs: birthday cakes, age displays, and lesson status badges.
struct StudentListRow: View {
    let student: Student
    let sortOrder: SortOrder
    let daysSinceLastLesson: Int?

    // MARK: - Context Menu Actions (optional)
    var onViewDetails: (() -> Void)?
    var onDelete: (() -> Void)?
    #if os(macOS)
    var onOpenInNewWindow: (() -> Void)?
    #endif

    @Environment(\.calendar) private var calendar
    
    private static let birthdayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt
    }()
    
    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
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

    private func copyStudentName() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(student.fullName, forType: .string)
        #else
        UIPasteboard.general.string = student.fullName
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            StudentAvatarView(student: student, size: 40)

            // Name only
            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .hoverableRow()
        .contextMenu {
            if let onViewDetails {
                Button {
                    onViewDetails()
                } label: {
                    Label("View Details", systemImage: "person.text.rectangle")
                }
            }

            #if os(macOS)
            Button {
                if let onOpenInNewWindow {
                    onOpenInNewWindow()
                } else {
                    openStudentInNewWindow(student.id)
                }
            } label: {
                Label("Open in New Window", systemImage: "uiwindow.split.2x1")
            }
            #endif

            Divider()

            Button {
                copyStudentName()
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }

            if let onDelete {
                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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
