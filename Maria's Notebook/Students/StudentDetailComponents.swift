// StudentDetailComponents.swift
// Reusable components extracted from StudentDetailView

import OSLog
import SwiftData
import SwiftUI

// MARK: - StudentEditForm

struct StudentEditForm: View {
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftNickname: String
    @Binding var draftBirthday: Date
    @Binding var draftLevel: Student.Level
    @Binding var draftStartDate: Date

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
                Text(Student.Level.lower.rawValue).tag(Student.Level.lower)
                Text(Student.Level.upper.rawValue).tag(Student.Level.upper)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }
}

// MARK: - StudentInfoRows

struct StudentInfoRows: View {
    let student: Student
    @Environment(\.modelContext) private var modelContext
    
    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return df
    }()
    
    private var formattedBirthday: String {
        Self.birthdayFormatter.string(from: student.birthday)
    }
    
    private var ageDescription: String {
        AgeUtils.verboseAgeString(for: student.birthday)
    }
    
    private var attendanceInfoRow: some View {
        AttendanceInfoRow(student: student)
    }

    var body: some View {
        VStack(spacing: 14) {
            InfoRowView(icon: "person", title: "Nickname", value: student.nickname ?? "-")
            InfoRowView(icon: "calendar", title: "Birthday", value: formattedBirthday)
            if let ds = student.dateStarted {
                InfoRowView(icon: "calendar.badge.clock", title: "Start Date", value: Self.birthdayFormatter.string(from: ds))
            }
            InfoRowView(icon: "gift", title: "Age", value: ageDescription)
            InfoRowView(icon: "graduationcap", title: "Florida Grade Equivalent", value: FloridaGradeCalculator.grade(for: student.birthday).displayString)
            DaysSinceLastLessonView(student: student)
            attendanceInfoRow
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }
}

// MARK: - AttendanceInfoRow

struct AttendanceInfoRow: View {
    private static let logger = Logger.students

    let student: Student
    @Environment(\.modelContext) private var modelContext
    
    private var daysTardyThisSchoolYear: Int {
        let calendar = Calendar.current
        let start = FloridaGradeCalculator.schoolYearStart(for: Date(), calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentIDString = student.id.uuidString
        let from = start
        let to = end
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { rec in
                rec.studentID == studentIDString && rec.date >= from && rec.date < to
            }
        )
        let records: [AttendanceRecord]
        do {
            records = try modelContext.fetch(descriptor)
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
        let studentIDString = student.id.uuidString
        let from = start
        let to = end
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { rec in
                rec.studentID == studentIDString && rec.date >= from && rec.date < to
            }
        )
        let records: [AttendanceRecord]
        do {
            records = try modelContext.fetch(descriptor)
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
