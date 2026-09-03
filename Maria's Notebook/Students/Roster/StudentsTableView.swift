#if os(macOS)
import AppKit
import SwiftUI

struct StudentsTableView: View {
    let students: [CDStudent]
    let nextLessonNames: [UUID: String]
    let lastObservationDates: [UUID: Date]
    let presentNowIDs: Set<UUID>
    @Binding var selectedStudentID: UUID?

    @State private var selection: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\StudentTableRow.name)]

    private var rows: [StudentTableRow] {
        students.compactMap { student in
            guard let id = student.id else { return nil }
            return StudentTableRow(
                id: id,
                student: student,
                name: student.fullName,
                level: student.level.rawValue,
                age: Self.ageString(for: student),
                ageSortValue: student.birthday?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude,
                birthdayLabel: student.birthday.map { DateFormatters.shortMonthDay.string(from: $0) },
                daysUntilBirthday: student.birthday.flatMap { AgeUtils.daysUntilNextBirthday(for: $0) },
                nextLesson: nextLessonNames[id] ?? "—",
                lastObservation: lastObservationDates[id]
            )
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Student", value: \.name) { row in
                HStack(spacing: 8) {
                    StudentAvatarView(student: row.student, size: 28)
                        .overlay(alignment: .bottomTrailing) {
                            if presentNowIDs.contains(row.id) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(.background, lineWidth: 1))
                            }
                        }
                    Text(row.name)
                        .lineLimit(1)
                }
                .contextMenu { contextMenu(for: row) }
            }
            .width(min: 170, ideal: 220)

            TableColumn("Level", value: \.level)
                .width(min: 80, ideal: 110)
            TableColumn("Age", value: \.ageSortValue) { row in
                Text(row.age)
            }
            .width(min: 55, ideal: 70)
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
            TableColumn("Next Lesson", value: \.nextLesson)
                .width(min: 140, ideal: 210)
            TableColumn("Last Observation", value: \.lastObservationSortValue) { row in
                if let date = row.lastObservation {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 150)
        }
        .onChange(of: selection) { _, newSelection in
            guard let id = newSelection.first else { return }
            selectedStudentID = id
            selection.removeAll()
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No Students", systemImage: "person.3")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for row: StudentTableRow) -> some View {
        Button("View Details", systemImage: "person.text.rectangle") {
            selectedStudentID = row.id
        }
        Button("Open in New Window", systemImage: "uiwindow.split.2x1") {
            openStudentInNewWindow(row.id)
        }
        Divider()
        Button("Copy Name", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.name, forType: .string)
        }
    }

    private static func ageString(for student: CDStudent) -> String {
        guard let birthday = student.birthday else { return "—" }
        return AgeUtils.quarterGlyphAgeString(for: birthday)
    }
}

private struct StudentTableRow: Identifiable {
    let id: UUID
    let student: CDStudent
    let name: String
    let level: String
    let age: String
    let ageSortValue: TimeInterval
    let birthdayLabel: String?
    let daysUntilBirthday: Int?
    let nextLesson: String
    let lastObservation: Date?

    var lastObservationSortValue: Date { lastObservation ?? .distantPast }
    /// Soonest birthday first; students without one sort to the end.
    var birthdaySortValue: Int { daysUntilBirthday ?? .max }
}
#endif
