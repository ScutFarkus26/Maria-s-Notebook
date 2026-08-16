// StudentDetailComponents.swift
// Reusable components extracted from StudentDetailView

import OSLog
import SwiftUI
import CoreData

// MARK: - StudentRecordHeader

/// Title and standing actions above the record's section picker.
struct StudentRecordHeader: View {
    let student: CDStudent
    let isEditing: Bool
    let onAddObservation: () -> Void
    let onStartMeeting: () -> Void
    let onPlanLessons: () -> Void
    let onOpenDocuments: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.titleSmall)
                Text("Student record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAddObservation) {
                Label("Add Observation", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            #if os(macOS)
            // Changing a child's level is routine at rollover, so the editor
            // gets a standing button here rather than living only behind the
            // overflow menu.
            Button(action: onEdit) {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .disabled(isEditing)
            .help("Edit name, nickname, birthday, level, and enrollment")
            #endif

            Menu {
                Button("Start Meeting", systemImage: "person.2", action: onStartMeeting)
                Button("Plan Lessons", systemImage: "sparkles", action: onPlanLessons)
                Button("Open Documents", systemImage: "folder", action: onOpenDocuments)

                Divider()

                Button("Edit Student", systemImage: "square.and.pencil", action: onEdit)
                Button("Delete Student", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Label("Student Actions", systemImage: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
}

// MARK: - StudentEditForm

struct StudentEditForm: View {
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftNickname: String
    @Binding var draftBirthday: Date
    @Binding var draftLevel: CDStudent.Level
    @Binding var draftStartDate: Date
    @Binding var draftEnrollmentStatus: CDStudent.EnrollmentStatus
    @Binding var draftDateWithdrawn: Date?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("First Name", text: $draftFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Last Name", text: $draftLastName)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Nickname", text: $draftNickname)
                .textFieldStyle(.roundedBorder)
            DatePicker("Birthday", selection: $draftBirthday, displayedComponents: .date)
            DatePicker("Start Date", selection: $draftStartDate, displayedComponents: .date)
            Picker("Level", selection: $draftLevel) {
                Text(CDStudent.Level.lower.rawValue).tag(CDStudent.Level.lower)
                Text(CDStudent.Level.upper.rawValue).tag(CDStudent.Level.upper)
                Text(CDStudent.Level.adolescent.rawValue).tag(CDStudent.Level.adolescent)
            }
            .pickerStyle(.segmented)

            Divider()

            Picker("Enrollment", selection: $draftEnrollmentStatus) {
                Text("Enrolled").tag(CDStudent.EnrollmentStatus.enrolled)
                Text("Withdrawn").tag(CDStudent.EnrollmentStatus.withdrawn)
                Text("Transferred").tag(CDStudent.EnrollmentStatus.transferred)
            }
            .pickerStyle(.segmented)
            .onChange(of: draftEnrollmentStatus) { _, newValue in
                // Both withdrawn and transferred share the departure date; a nil date
                // would make the student look active in every past school-year lens.
                if newValue != .enrolled && draftDateWithdrawn == nil {
                    draftDateWithdrawn = Date()
                } else if newValue == .enrolled {
                    draftDateWithdrawn = nil
                }
            }

            if draftEnrollmentStatus != .enrolled {
                DatePicker(
                    "Date Departed",
                    selection: Binding(
                        get: { draftDateWithdrawn ?? Date() },
                        set: { draftDateWithdrawn = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }
}

// MARK: - Departure Banner

/// Banner shown on a former student's profile; covers both withdrawn and transferred.
struct DepartureBanner: View {
    let status: CDStudent.EnrollmentStatus
    let dateDeparted: Date?

    private var title: String {
        status == .transferred ? "Transferred" : "Withdrawn"
    }

    private var icon: String {
        status == .transferred ? "arrow.right.square" : "person.badge.minus"
    }

    private var background: Color {
        status == .transferred ? .indigo : .gray
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .font(AppTheme.ScaledFont.calloutSemibold)
            if let date = dateDeparted {
                Text("on \(DateFormatters.mediumDate.string(from: date))")
                    .font(AppTheme.ScaledFont.callout)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.top, AppTheme.Spacing.small)
    }
}

// MARK: - StudentInfoRows

struct StudentInfoRows: View {
    let student: CDStudent
    /// Two-column layout for wide panes (macOS / iPad regular) so label-value
    /// pairs don't stretch across the full detail width.
    var useGrid: Bool = false
    @Environment(\.managedObjectContext) private var viewContext

    private var formattedBirthday: String {
        DateFormatters.longDate.string(from: student.birthday ?? Date())
    }

    private var ageDescription: String {
        AgeUtils.verboseAgeString(for: student.birthday ?? Date())
    }

    private func promotionDescription(from previous: CDStudent.Level) -> String {
        var text = "\(previous.rawValue) → \(student.level.rawValue)"
        if let date = student.dateLastPromoted {
            text += " on \(DateFormatters.mediumDate.string(from: date))"
        }
        return text
    }

    private var attendanceInfoRow: some View {
        AttendanceInfoRow(student: student)
    }

    var body: some View {
        Group {
            if useGrid {
                // Adaptive: two columns only when each cell gets >=380pt, so labels
                // like "Florida Grade Equivalent" never wrap (narrow iPad panes get one column).
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 380, maximum: .infinity), spacing: 40)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    rowsContent
                }
            } else {
                VStack(spacing: 14) {
                    rowsContent
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    @ViewBuilder
    private var rowsContent: some View {
        InfoRowView(icon: "person", title: "Nickname", value: student.nickname ?? "-")
        InfoRowView(icon: "calendar", title: "Birthday", value: formattedBirthday)
        if let ds = student.dateStarted {
            InfoRowView(
                icon: "calendar.badge.clock", title: "Start Date",
                value: DateFormatters.longDate.string(from: ds)
            )
        }
        InfoRowView(icon: "gift", title: "Age", value: ageDescription)
        InfoRowView(
            icon: "graduationcap", title: "Florida Grade Equivalent",
            value: FloridaGradeCalculator.grade(for: student.birthday ?? Date()).displayString
        )
        if let previous = student.previousLevel {
            InfoRowView(icon: "arrow.up.circle", title: "Promoted", value: promotionDescription(from: previous))
        }
        DaysSinceLastLessonView(student: student)
        attendanceInfoRow
    }
}

// MARK: - AttendanceInfoRow

struct AttendanceInfoRow: View {
    private static let logger = Logger.students

    let student: CDStudent
    @Environment(\.managedObjectContext) private var viewContext
    
    private var daysTardyThisSchoolYear: Int {
        let calendar = Calendar.current
        let start = FloridaGradeCalculator.schoolYearStart(for: Date(), calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentIDString = student.id?.uuidString ?? ""
        let from = start
        let to = end
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "AttendanceRecord")
        descriptor.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@ AND date < %@",
            studentIDString, from as CVarArg, to as CVarArg
        )
        let records: [CDAttendanceRecord]
        do {
            records = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch tardy records: \(error)")
            records = []
        }
        return records.filter { $0.status == .tardy }.count
    }

    private var daysAbsentThisSchoolYear: Int {
        let calendar = Calendar.current
        let start = FloridaGradeCalculator.schoolYearStart(for: Date(), calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentIDString = student.id?.uuidString ?? ""
        let from = start
        let to = end
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "AttendanceRecord")
        descriptor.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@ AND date < %@",
            studentIDString, from as CVarArg, to as CVarArg
        )
        let records: [CDAttendanceRecord]
        do {
            records = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch absent records: \(error)")
            records = []
        }
        return records.filter { $0.status == .absent }.count
    }
    
    private func metricBadge(label: String, count: Int, color: Color) -> some View {
        StatusPill(
            text: "\(label) \(count)",
            color: color,
            icon: nil
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Attendance (This School Year)")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: AppTheme.Spacing.small) {
                metricBadge(label: "Tardy", count: daysTardyThisSchoolYear, color: .blue)
                metricBadge(label: "Absent", count: daysAbsentThisSchoolYear, color: .red)
            }
        }
    }
}
