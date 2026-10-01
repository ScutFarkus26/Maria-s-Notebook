import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A row in the roster list.
///
/// Every enrolled row reads the same whatever the sort: the child's name, any
/// mark worth seeing today (absent, left early, a birthday this week), and a
/// second line with the two signals a guide scans for — school days since the
/// last lesson and when the child was last observed, in orange when either
/// has gone stale. The sort only adds a labeled trailing value (an age, a
/// birthday) when it orders by one; it never changes what the other text means.
struct StudentListRow: View {
    let student: CDStudent
    let sortOrder: SortOrder
    /// Nil for a former student, whose row shows that status instead.
    let signals: StudentSignals?
    var onAddObservation: (() -> Void)?
    var onGiveLesson: (() -> Void)?

    @Environment(\.calendar) private var calendar

    private var presence: StudentSignals.Presence { signals?.presence ?? .unmarked }
    private var isAway: Bool { presence == .absent || presence == .leftEarly }

    private var soonBirthdayDays: Int? {
        guard student.isEnrolled else { return nil }
        return RosterSignalRules.daysUntilSoonBirthday(student.birthday, calendar: calendar)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 40)
                .opacity(isAway ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if presence == .here {
                        Circle()
                            .fill(.green)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(student.fullName)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(student.isEnrolled ? .primary : .secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let tag = presenceTag {
                        RosterTag(text: tag, tint: .secondary)
                    }
                    if let days = soonBirthdayDays {
                        RosterTag(text: RosterSignalText.birthday(inDays: days, calendar: calendar), tint: .orange)
                    }
                }
                secondLine
                    .font(AppTheme.ScaledFont.caption)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if student.isEnrolled, let accessory = sortAccessory {
                Text(accessory)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .hoverableRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .contextMenu { contextMenu }
    }

    // MARK: - Pieces

    private var presenceTag: String? {
        switch presence {
        case .absent: return "Absent"
        case .leftEarly: return "Left Early"
        case .here, .unmarked: return nil
        }
    }

    @ViewBuilder
    private var secondLine: some View {
        if let signals {
            let lesson = Text(RosterSignalText.lesson(signals.schoolDaysSinceLesson))
                .foregroundStyle(signals.isDueForLesson ? Color.orange : Color.secondary)
                .fontWeight(signals.isDueForLesson ? .semibold : .regular)
            let observed = Text(RosterSignalText.observed(signals.lastObserved, calendar: calendar))
                .foregroundStyle(signals.isObservationStale(calendar: calendar) ? Color.orange : Color.secondary)
            // One line where it fits; in a narrow sidebar, one signal per line
            // rather than cutting the second off.
            ViewThatFits(in: .horizontal) {
                Text("\(lesson)\(Text(" · ").foregroundStyle(.tertiary))\(observed)")
                    .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    lesson
                    observed
                }
            }
        } else {
            Text(student.isTransferred ? "Transferred" : "Withdrawn")
                .foregroundStyle(.tertiary)
        }
    }

    /// The labeled value of the active sort, when it sorts by one.
    private var sortAccessory: String? {
        switch sortOrder {
        case .age:
            guard let birthday = student.birthday else { return nil }
            return "Age \(AgeUtils.quarterGlyphAgeString(for: birthday))"
        case .birthday:
            guard student.birthday != nil else { return nil }
            let next = RosterBirthday.nextOccurrence(of: student.birthday, using: calendar)
            return DateFormatters.shortMonthDay.string(from: next)
        case .alphabetical, .manual:
            return nil
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let onAddObservation {
            Button("Add Observation", systemImage: "square.and.pencil", action: onAddObservation)
        }
        if let onGiveLesson {
            Button("Give Lesson…", systemImage: "book", action: onGiveLesson)
        }
        if onAddObservation != nil || onGiveLesson != nil {
            Divider()
        }
        #if os(macOS)
        Button("Open in New Window", systemImage: "uiwindow.split.2x1") {
            if let id = student.id { openStudentInNewWindow(id) }
        }
        #endif
        Button("Copy Name", systemImage: "doc.on.doc") {
            Pasteboard.copy(student.fullName)
        }
    }

    private var accessibilityDescription: String {
        var parts = [student.fullName]
        switch presence {
        case .here: parts.append("here today")
        case .absent: parts.append("absent today")
        case .leftEarly: parts.append("left early today")
        case .unmarked: break
        }
        if let days = soonBirthdayDays {
            parts.append(RosterSignalText.birthday(inDays: days, calendar: calendar))
        }
        if let signals {
            parts.append(RosterSignalText.lesson(signals.schoolDaysSinceLesson))
            parts.append(RosterSignalText.observed(signals.lastObserved, calendar: calendar))
        } else {
            parts.append(student.isTransferred ? "transferred" : "withdrawn")
        }
        if let sortAccessory { parts.append(sortAccessory) }
        return parts.joined(separator: ", ")
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct StudentListRowPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext
        let student = CDStudent(context: ctx)
        student.firstName = "John"
        student.lastName = "Doe"
        student.birthday = Date()
        student.level = .upper

        return List {
            StudentListRow(
                student: student, sortOrder: .alphabetical,
                signals: StudentSignals(presence: .here, schoolDaysSinceLesson: 2, lastObserved: Date())
            )
            StudentListRow(
                student: student, sortOrder: .age,
                signals: StudentSignals(presence: .absent, schoolDaysSinceLesson: 11, lastObserved: nil)
            )
        }
        .previewEnvironment(using: stack)
    }
}

#Preview {
    StudentListRowPreview()
}
