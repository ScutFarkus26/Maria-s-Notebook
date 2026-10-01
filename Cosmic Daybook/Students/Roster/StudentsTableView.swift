#if os(macOS)
import AppKit
import SwiftUI

/// The Mac roster: one row per child, the open child highlighted, so the
/// arrow keys walk the class and the record beside the table follows.
///
/// The visible columns are the signals a guide scans for (lesson age, last
/// observed, next lesson); Age and Birthday are there too, hidden until chosen
/// from the header's context menu, and every column sorts.
struct StudentsTableView: View {
    let students: [CDStudent]
    let signals: (UUID) -> StudentSignals
    /// False for the former-students list, whose rows carry no signals.
    let showsSignals: Bool
    @Binding var selectedStudentID: UUID?
    let onAddObservation: (CDStudent) -> Void
    let onGiveLesson: (CDStudent) -> Void

    @Environment(\.calendar) private var calendar
    @State private var sortOrder = [KeyPathComparator(\StudentTableRow.name)]
    @SceneStorage("StudentsTable.columns") private var columnCustomization: TableColumnCustomization<StudentTableRow>

    private var rows: [StudentTableRow] {
        students.compactMap { student in
            guard let id = student.id else { return nil }
            let s = signals(id)
            return StudentTableRow(
                id: id,
                student: student,
                name: student.fullName,
                level: student.level,
                presence: showsSignals ? s.presence : .unmarked,
                schoolDaysSinceLesson: s.schoolDaysSinceLesson,
                isDue: showsSignals && s.isDueForLesson,
                lastObserved: s.lastObserved,
                isObservationStale: showsSignals && s.isObservationStale(calendar: calendar),
                nextLesson: s.nextLessonName ?? "—",
                age: student.birthday.map { AgeUtils.quarterGlyphAgeString(for: $0) } ?? "—",
                ageSortValue: student.birthday?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude,
                birthdayLabel: student.birthday.map { DateFormatters.shortMonthDay.string(from: $0) },
                daysUntilBirthday: student.birthday.flatMap { AgeUtils.daysUntilNextBirthday(for: $0) },
                soonBirthdayDays: showsSignals
                    ? RosterSignalRules.daysUntilSoonBirthday(student.birthday, calendar: calendar)
                    : nil
            )
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selectedStudentID, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Student", value: \.name) { row in
                studentCell(row)
            }
            .width(min: 170, ideal: 230)
            .customizationID("student")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Level", value: \.levelSortValue) { row in
                LevelBadge(level: row.level)
            }
            .width(min: 80, ideal: 96)
            .customizationID("level")

            TableColumn("Last Lesson", value: \.lessonSortValue) { row in
                if showsSignals {
                    Text(RosterSignalText.lessonShort(row.schoolDaysSinceLesson))
                        .foregroundStyle(row.isDue ? Color.orange : Color.primary)
                        .fontWeight(row.isDue ? .semibold : .regular)
                }
            }
            .width(min: 80, ideal: 100)
            .customizationID("lastLesson")

            TableColumn("Observed", value: \.lastObservedSortValue) { row in
                if showsSignals {
                    Text(RosterSignalText.observedShort(row.lastObserved, calendar: calendar))
                        .foregroundStyle(row.isObservationStale ? Color.orange : Color.primary)
                }
            }
            .width(min: 90, ideal: 110)
            .customizationID("observed")

            TableColumn("Next Lesson", value: \.nextLesson)
                .width(min: 120, ideal: 170)
                .customizationID("nextLesson")

            TableColumn("Age", value: \.ageSortValue) { row in
                Text(row.age)
            }
            .width(min: 55, ideal: 70)
            .customizationID("age")
            .defaultVisibility(.hidden)

            TableColumn("Birthday", value: \.birthdaySortValue) { row in
                if let label = row.birthdayLabel, let days = row.daysUntilBirthday {
                    HStack(spacing: 6) {
                        Text(label)
                        Text(AgeUtils.birthdayCountdownString(days: days))
                            .foregroundStyle(days == 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    .lineLimit(1)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160)
            .customizationID("birthday")
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                contextMenu(for: row)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No Students", systemImage: "person.3")
            }
        }
    }

    private func studentCell(_ row: StudentTableRow) -> some View {
        let isAway = row.presence == .absent || row.presence == .leftEarly
        return HStack(spacing: 8) {
            StudentAvatarView(student: row.student, size: 24)
                .opacity(isAway ? 0.55 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if row.presence == .here {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.background, lineWidth: 1))
                    }
                }
            Text(row.name)
                .lineLimit(1)
            if row.presence == .absent {
                RosterTag(text: "Absent", tint: .secondary)
            } else if row.presence == .leftEarly {
                RosterTag(text: "Left Early", tint: .secondary)
            }
            if let days = row.soonBirthdayDays {
                RosterTag(text: RosterSignalText.birthday(inDays: days, calendar: calendar), tint: .orange)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for row: StudentTableRow) -> some View {
        if showsSignals {
            Button("Add Observation", systemImage: "square.and.pencil") {
                onAddObservation(row.student)
            }
            Button("Give Lesson…", systemImage: "book") {
                onGiveLesson(row.student)
            }
            Divider()
        }
        Button("Open in New Window", systemImage: "uiwindow.split.2x1") {
            openStudentInNewWindow(row.id)
        }
        Button("Copy Name", systemImage: "doc.on.doc") {
            Pasteboard.copy(row.name)
        }
    }
}

nonisolated struct StudentTableRow: Identifiable {
    let id: UUID
    let student: CDStudent
    let name: String
    let level: CDStudent.Level
    let presence: StudentSignals.Presence
    let schoolDaysSinceLesson: Int?
    let isDue: Bool
    let lastObserved: Date?
    let isObservationStale: Bool
    let nextLesson: String
    let age: String
    let ageSortValue: TimeInterval
    let birthdayLabel: String?
    let daysUntilBirthday: Int?
    let soonBirthdayDays: Int?

    /// Youngest level first, the order the iPhone and iPad sections use.
    var levelSortValue: Int { CDStudent.Level.allCases.firstIndex(of: level) ?? 0 }
    /// Longest without a lesson last when ascending; none at all after that.
    var lessonSortValue: Int { schoolDaysSinceLesson ?? .max }
    var lastObservedSortValue: Date { lastObserved ?? .distantPast }
    /// Soonest birthday first; students without one sort to the end.
    var birthdaySortValue: Int { daysUntilBirthday ?? .max }
}
#endif
