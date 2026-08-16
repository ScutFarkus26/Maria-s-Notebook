import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A row component for displaying a student in the roster list.
/// Shows the level-colored avatar with a present-today indicator, the student's
/// name, and a trailing accessory that follows the active sort: next birthday
/// (with countdown), quarter-rounded age, or days since the last lesson.
struct StudentListRow: View {
    let student: CDStudent
    let sortOrder: SortOrder
    let daysSinceLastLesson: Int?
    var isPresentToday: Bool = false

    @Environment(\.calendar) private var calendar

    // MARK: - Birthday Computations

    private var nextBirthdayDate: Date {
        let today = Date()
        let comps = calendar.dateComponents([.month, .day], from: student.birthday ?? Date())
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

    private var daysUntilNextBirthday: Int {
        let start = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: nextBirthdayDate)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    private var birthdayDateString: String {
        DateFormatters.shortMonthDay.string(from: nextBirthdayDate)
    }

    // MARK: - Age Computations

    private var ageDisplayString: String {
        let quarter = AgeUtils.quarterRoundedAgeComponents(birthday: student.birthday ?? Date())
        switch quarter.months {
        case 3: return "\(quarter.years) 1/4"
        case 6: return "\(quarter.years) 1/2"
        case 9: return "\(quarter.years) 3/4"
        default: return "\(quarter.years)"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    if isPresentToday {
                        Circle()
                            .fill(.green)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                            .accessibilityHidden(true)
                    }
                }

            Text(student.fullName)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(student.isEnrolled ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                // In a squeezed column the name must win over the trailing accessory.
                .layoutPriority(1)

            Spacer(minLength: 8)

            if student.isEnrolled {
                trailingAccessory
                    .accessibilityHidden(true)
            } else {
                Text(student.isTransferred ? "Transferred" : "Withdrawn")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .hoverableRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .contextMenu {
            #if os(macOS)
            Button {
                if let id = student.id { openStudentInNewWindow(id) }
            } label: {
                Label("Open in New Window", systemImage: "uiwindow.split.2x1")
            }

            Divider()
            #endif

            Button {
                copyStudentName()
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Trailing Accessory

    @ViewBuilder
    private var trailingAccessory: some View {
        switch sortOrder {
        case .birthday:
            birthdayAccessory
        case .age:
            Text(ageDisplayString)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
        case .alphabetical, .manual:
            lessonAccessory
        }
    }

    @ViewBuilder
    private var birthdayAccessory: some View {
        let days = daysUntilNextBirthday
        let isSoon = days <= 7
        HStack(spacing: 4) {
            if isSoon {
                Image(systemName: "gift")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(days == 0 ? "Today!" : "\(birthdayDateString) · \(days)d")
        }
        .font(isSoon ? AppTheme.ScaledFont.captionSemibold : AppTheme.ScaledFont.caption)
        .foregroundStyle(isSoon ? Color.orange : Color.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var lessonAccessory: some View {
        if let days = daysSinceLastLesson {
            if days >= 0 {
                HStack(spacing: 3) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 10, weight: .medium))
                    Text(days == 0 ? "Today" : "\(days)d")
                }
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("No lessons")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Helpers

    private var accessibilityDescription: String {
        var parts = [student.fullName]
        if isPresentToday { parts.append("present today") }
        if !student.isEnrolled { parts.append(student.isTransferred ? "transferred" : "withdrawn") }
        switch sortOrder {
        case .birthday:
            parts.append("birthday \(birthdayDateString)")
        case .age:
            parts.append("age \(ageDisplayString)")
        case .alphabetical, .manual:
            if let days = daysSinceLastLesson, days >= 0 {
                parts.append("\(days) days since last lesson")
            }
        }
        return parts.joined(separator: ", ")
    }

    private func copyStudentName() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(student.fullName, forType: .string)
        #else
        UIPasteboard.general.string = student.fullName
        #endif
    }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let student = CDStudent(context: ctx)
    student.firstName = "John"
    student.lastName = "Doe"
    student.birthday = Date()
    student.level = .upper

    return List {
        StudentListRow(student: student, sortOrder: .alphabetical, daysSinceLastLesson: 12, isPresentToday: true)
        StudentListRow(student: student, sortOrder: .birthday, daysSinceLastLesson: nil)
        StudentListRow(student: student, sortOrder: .age, daysSinceLastLesson: nil)
    }
    .previewEnvironment(using: stack)
}
