// StudentDetailComponents.swift
// Reusable components extracted from StudentDetailView

import OSLog
import SwiftUI
import CoreData

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
            }
            .pickerStyle(.segmented)

            Divider()

            Picker("Enrollment", selection: $draftEnrollmentStatus) {
                Text("Enrolled").tag(CDStudent.EnrollmentStatus.enrolled)
                Text("Withdrawn").tag(CDStudent.EnrollmentStatus.withdrawn)
            }
            .pickerStyle(.segmented)
            .onChange(of: draftEnrollmentStatus) { _, newValue in
                if newValue == .withdrawn && draftDateWithdrawn == nil {
                    draftDateWithdrawn = Date()
                } else if newValue == .enrolled {
                    draftDateWithdrawn = nil
                }
            }

            if draftEnrollmentStatus == .withdrawn {
                DatePicker(
                    "Date Withdrawn",
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

// MARK: - Withdrawn Banner

struct WithdrawnBanner: View {
    let dateWithdrawn: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.badge.minus")
            Text("Withdrawn")
                .font(AppTheme.ScaledFont.calloutSemibold)
            if let date = dateWithdrawn {
                Text("on \(DateFormatters.mediumDate.string(from: date))")
                    .font(AppTheme.ScaledFont.callout)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(.gray, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.top, AppTheme.Spacing.small)
    }
}

// MARK: - StudentInfoRows

struct StudentInfoRows: View {
    let student: CDStudent
    @Environment(\.managedObjectContext) private var viewContext
    
    private var formattedBirthday: String {
        DateFormatters.longDate.string(from: student.birthday ?? Date())
    }

    private var ageDescription: String {
        AgeUtils.verboseAgeString(for: student.birthday ?? Date())
    }
    
    private var attendanceInfoRow: some View {
        AttendanceInfoRow(student: student)
    }

    var body: some View {
        VStack(spacing: 14) {
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
            DaysSinceLastLessonView(student: student)
            attendanceInfoRow
        }
        .padding(.horizontal, AppTheme.Spacing.small)
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
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "CDAttendanceRecord")
        descriptor.predicate = NSPredicate(format: "studentID == %@ AND date >= %@ AND date < %@", studentIDString, from as CVarArg, to as CVarArg)
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
        let descriptor: NSFetchRequest<CDAttendanceRecord> = NSFetchRequest(entityName: "CDAttendanceRecord")
        descriptor.predicate = NSPredicate(format: "studentID == %@ AND date >= %@ AND date < %@", studentIDString, from as CVarArg, to as CVarArg)
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
