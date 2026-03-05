import Foundation
import SwiftData

// MARK: - Calendar & Meetings

extension BackupEntityImporter {

    // MARK: - Student Meetings

    /// Imports student meetings from DTOs.
    static func importStudentMeetings(
        _ dtos: [StudentMeetingDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<StudentMeeting>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let meeting = StudentMeeting(id: dto.id, studentID: dto.studentID, date: dto.date)
            meeting.completed = dto.completed
            meeting.reflection = dto.reflection
            meeting.focus = dto.focus
            meeting.requests = dto.requests
            meeting.guideNotes = dto.guideNotes
            return meeting
        })
    }

    // MARK: - Attendance Records

    /// Imports attendance records from DTOs.
    static func importAttendanceRecords(
        _ dtos: [AttendanceRecordDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<AttendanceRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let absenceReason = dto.absenceReason
                    .flatMap { AbsenceReason(rawValue: $0) } ?? .none
                let status = AttendanceStatus(
                    rawValue: dto.status
                ) ?? .unmarked
                return AttendanceRecord(
                    id: dto.id, studentID: dto.studentID,
                    date: dto.date, status: status,
                    absenceReason: absenceReason
                )
            }
        )
    }

    // MARK: - Meeting Templates

    static func importMeetingTemplates(
        _ dtos: [MeetingTemplateDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<MeetingTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            MeetingTemplate(
                id: dto.id,
                createdAt: dto.createdAt,
                name: dto.name,
                reflectionPrompt: dto.reflectionPrompt,
                focusPrompt: dto.focusPrompt,
                requestsPrompt: dto.requestsPrompt,
                guideNotesPrompt: dto.guideNotesPrompt,
                sortOrder: dto.sortOrder,
                isActive: dto.isActive,
                isBuiltIn: dto.isBuiltIn
            )
        })
    }

    // MARK: - Reminders

    static func importReminders(
        _ dtos: [ReminderDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Reminder>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            Reminder(
                id: dto.id,
                title: dto.title,
                notes: dto.notes,
                dueDate: dto.dueDate,
                isCompleted: dto.isCompleted,
                completedAt: dto.completedAt,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
        })
    }

    // MARK: - Calendar Events

    static func importCalendarEvents(
        _ dtos: [CalendarEventDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<CalendarEvent>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let e = CalendarEvent(
                id: dto.id,
                title: dto.title,
                startDate: dto.startDate,
                endDate: dto.endDate,
                location: dto.location,
                notes: dto.notes,
                isAllDay: dto.isAllDay
            )
            return e
        })
    }
}
