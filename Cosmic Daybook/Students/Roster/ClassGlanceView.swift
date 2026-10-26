import SwiftUI
import CoreData

/// The class today, for the empty half of the Students screen (iPad, Mac)
/// when no child is open: who's away, who's due for a lesson, who hasn't been
/// observed lately, and whose birthday is coming. Every name opens the record.
///
/// It replaces the card grid that used to fill this space with a second copy
/// of the roster beside the first.
struct ClassGlanceView: View {
    let glance: ClassGlance
    let onSelect: (UUID) -> Void
    let onShowScope: (StudentsFilter) -> Void

    @Environment(\.appRouter) private var appRouter

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(glance.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    #if os(macOS)
                    // On iPad the navigation bar carries the title.
                    Text("Class at a Glance")
                        .font(AppTheme.ScaledFont.titleLarge)
                    #endif
                }

                attendanceCard

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    card(
                        "Due for a Lesson",
                        subtitle: "No lesson in \(RosterSignalRules.dueSchoolDays) or more school days",
                        entries: glance.due,
                        empty: "Everyone has had a lesson recently.",
                        moreScope: .dueForLesson
                    )
                    card(
                        "Not Observed Lately",
                        subtitle: "No observation in \(RosterSignalRules.observationStaleDays / 7) weeks or more",
                        entries: glance.unobserved,
                        empty: "Everyone has been observed recently."
                    )
                    if !glance.birthdays.isEmpty {
                        card(
                            "Birthdays This Week",
                            subtitle: "Today and the next \(RosterSignalRules.birthdaySoonDays) days",
                            entries: glance.birthdays,
                            empty: ""
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .background(AppTheme.Colors.paneBackground)
    }

    // MARK: - Attendance

    private var attendanceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            if glance.attendanceTaken {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(glance.hereCount)")
                        .font(AppTheme.ScaledFont.titleLarge)
                    Text("of \(glance.enrolledCount) here")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.secondary)
                }
                if !glance.away.isEmpty {
                    Divider().frame(height: 28)
                    FlowNames(entries: glance.away, onSelect: onSelect)
                }
            } else {
                Label("Attendance not taken yet", systemImage: "checklist")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(glance.attendanceTaken ? "Attendance" : "Take Attendance") {
                appRouter.navigateTo(.attendance)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(AppTheme.Colors.controlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Cards

    private static let visibleRows = 6

    private func card(
        _ title: String,
        subtitle: String,
        entries: [ClassGlance.Entry],
        empty: String,
        moreScope: StudentsFilter? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
            Text(subtitle)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            if entries.isEmpty {
                Text(empty)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(entries.prefix(Self.visibleRows)) { entry in
                Divider()
                Button { onSelect(entry.studentID) } label: {
                    HStack(spacing: 10) {
                        StudentAvatarView(student: entry.student, size: 28)
                        Text(entry.student.fullName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(entry.value)
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(entry.isWarning ? Color.orange : Color.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if entries.count > Self.visibleRows {
                Divider()
                let more = entries.count - Self.visibleRows
                if let moreScope {
                    Button("\(more) more") { onShowScope(moreScope) }
                        .buttonStyle(.borderless)
                        .padding(.top, 8)
                } else {
                    Text("\(more) more")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.controlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Names of children away today, each opening the record.
private struct FlowNames: View {
    let entries: [ClassGlance.Entry]
    let onSelect: (UUID) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { pills }
            Text(entries.map { "\($0.student.shortName) (\($0.value.lowercased()))" }.joined(separator: ", "))
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var pills: some View {
        ForEach(entries) { entry in
            Button { onSelect(entry.studentID) } label: {
                HStack(spacing: 4) {
                    Text(entry.student.shortName)
                    Text(entry.value)
                        .foregroundStyle(.secondary)
                }
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .capsuleFill(Color.secondary.opacity(UIConstants.OpacityConstants.light))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Model

/// What the glance shows, built once from the visible roster and its signals.
struct ClassGlance {
    struct Entry: Identifiable {
        let student: CDStudent
        let studentID: UUID
        let value: String
        let isWarning: Bool
        /// A Hebrew birthday line: a child whose two birthdays fall in the
        /// same week has two lines in Birthdays This Week.
        var isHebrewBirthday = false

        var id: String { isHebrewBirthday ? "\(studentID)-hebrew" : studentID.uuidString }
    }

    let date: Date
    let enrolledCount: Int
    let hereCount: Int
    let attendanceTaken: Bool
    let away: [Entry]
    let due: [Entry]
    let unobserved: [Entry]
    let birthdays: [Entry]

    /// - Parameter students: the enrolled, visible roster for the selected school year.
    static func make(
        students: [CDStudent],
        signals: (UUID) -> StudentSignals,
        attendanceTaken: Bool,
        calendar: Calendar,
        now: Date = Date()
    ) -> ClassGlance {
        var here = 0
        var away: [Entry] = []
        var due: [(Entry, Int)] = []
        var unobserved: [(Entry, Date)] = []
        var birthdays: [(entry: Entry, days: Int)] = []

        for student in students {
            guard let id = student.id else { continue }
            let s = signals(id)
            switch s.presence {
            case .here: here += 1
            case .absent: away.append(Entry(student: student, studentID: id, value: "Absent", isWarning: false))
            case .leftEarly: away.append(Entry(student: student, studentID: id, value: "Left Early", isWarning: false))
            case .unmarked: break
            }
            if s.isDueForLesson {
                let entry = Entry(
                    student: student, studentID: id,
                    value: RosterSignalText.lessonShort(s.schoolDaysSinceLesson), isWarning: true
                )
                due.append((entry, s.schoolDaysSinceLesson ?? .max))
            }
            if s.isObservationStale(now: now, calendar: calendar) {
                let entry = Entry(
                    student: student, studentID: id,
                    value: RosterSignalText.observedShort(s.lastObserved, calendar: calendar, now: now),
                    isWarning: true
                )
                unobserved.append((entry, s.lastObserved ?? .distantPast))
            }
            birthdays += [
                birthdayEntry(student, id: id, calendar: calendar, today: now),
                hebrewBirthdayEntry(student, id: id, today: now)
            ].compactMap { $0 }
        }

        return ClassGlance(
            date: now,
            enrolledCount: students.count,
            hereCount: here,
            attendanceTaken: attendanceTaken,
            away: away,
            due: due.sorted { $0.1 > $1.1 }.map(\.0),
            unobserved: unobserved.sorted { $0.1 < $1.1 }.map(\.0),
            birthdays: birthdays.sorted {
                ($0.days, $0.entry.isHebrewBirthday ? 1 : 0) < ($1.days, $1.entry.isHebrewBirthday ? 1 : 0)
            }.map(\.entry)
        )
    }

    /// "Turns 10 Tue" when the child's birthday falls in the coming week.
    private static func birthdayEntry(
        _ student: CDStudent, id: UUID, calendar: Calendar, today: Date
    ) -> (entry: Entry, days: Int)? {
        guard let days = RosterSignalRules.daysUntilSoonBirthday(student.birthday, calendar: calendar, today: today)
        else { return nil }
        let turning = turningAge(student.birthday, inDays: days, calendar: calendar, today: today)
        let when = days == 0 ? "today" : RosterSignalText.birthday(inDays: days, calendar: calendar, today: today)
            .replacingOccurrences(of: "Birthday ", with: "")
        let value = turning.map { "Turns \($0) \(when)" } ?? (days == 0 ? "Today" : when)
        return (Entry(student: student, studentID: id, value: value, isWarning: days == 0), days)
    }

    /// "Hebrew birthday · 14 Adar II, Tue" when the child's Hebrew birthday
    /// falls in the same window as the Gregorian one. Read with the app's
    /// Gregorian calendar, never the device's (`HebrewBirthday`).
    private static func hebrewBirthdayEntry(
        _ student: CDStudent, id: UUID, today: Date
    ) -> (entry: Entry, days: Int)? {
        let calendar = AppCalendar.shared
        guard let days = RosterSignalRules.daysUntilSoonHebrewBirthday(
                student.birthday, bornAfterSunset: student.bornAfterSunset, calendar: calendar, today: today
              ),
              let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)),
              let dayAndMonth = HebrewBirthday.englishDayAndMonth(on: day, calendar: calendar)
        else { return nil }
        let when = days == 0 ? "today" : day.formatted(.dateTime.weekday(.abbreviated))
        let entry = Entry(
            student: student, studentID: id,
            value: "Hebrew birthday · \(dayAndMonth), \(when)", isWarning: days == 0,
            isHebrewBirthday: true
        )
        return (entry, days)
    }

    private static func turningAge(_ birthday: Date?, inDays days: Int, calendar: Calendar, today: Date) -> Int? {
        guard let birthday, let day = calendar.date(byAdding: .day, value: days, to: today) else { return nil }
        let age = calendar.component(.year, from: day) - calendar.component(.year, from: birthday)
        return age > 0 ? age : nil
    }
}
