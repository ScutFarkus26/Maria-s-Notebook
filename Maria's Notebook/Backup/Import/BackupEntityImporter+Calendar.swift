import Foundation
import CoreData

// MARK: - Calendar & Meetings

extension BackupEntityImporter {

    // MARK: - CDStudent Meetings

    /// Imports student meetings from DTOs.
    static func importStudentMeetings(
        _ dtos: [StudentMeetingDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDStudentMeeting>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let meeting = CDStudentMeeting(context: viewContext)
            meeting.id = dto.id
            meeting.studentID = dto.studentID.uuidString
            meeting.date = dto.date
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
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDAttendanceRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let absenceReason = dto.absenceReason
                    .flatMap { AbsenceReason(rawValue: $0) } ?? .none
                let status = AttendanceStatus(
                    rawValue: dto.status
                ) ?? .unmarked
                let record = CDAttendanceRecord(context: viewContext)
                record.id = dto.id
                record.studentID = dto.studentID.uuidString
                record.date = dto.date
                record.statusRaw = status.rawValue
                record.absenceReasonRaw = absenceReason.rawValue
                return record
            }
        )
    }

    // MARK: - Meeting Templates

    static func importMeetingTemplates(
        _ dtos: [MeetingTemplateDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDMeetingTemplate>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let mt = CDMeetingTemplate(context: viewContext)
            mt.id = dto.id
            mt.createdAt = dto.createdAt
            mt.name = dto.name
            mt.reflectionPrompt = dto.reflectionPrompt
            mt.focusPrompt = dto.focusPrompt
            mt.requestsPrompt = dto.requestsPrompt
            mt.guideNotesPrompt = dto.guideNotesPrompt
            mt.sortOrder = Int64(dto.sortOrder)
            mt.isActive = dto.isActive
            mt.isBuiltIn = dto.isBuiltIn
            return mt
        })
    }

    // MARK: - Reminders

    static func importReminders(
        _ dtos: [ReminderDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDReminder>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let r = CDReminder(context: viewContext)
            r.id = dto.id
            r.title = dto.title
            r.notes = dto.notes
            r.dueDate = dto.dueDate
            r.isCompleted = dto.isCompleted
            r.completedAt = dto.completedAt
            r.createdAt = dto.createdAt
            r.updatedAt = dto.updatedAt
            return r
        })
    }

    // MARK: - Calendar Events

    static func importCalendarEvents(
        _ dtos: [CalendarEventDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDCalendarEvent>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let e = CDCalendarEvent(context: viewContext)
            e.id = dto.id
            e.title = dto.title
            e.startDate = dto.startDate
            e.endDate = dto.endDate
            e.location = dto.location
            e.notes = dto.notes
            e.isAllDay = dto.isAllDay
            return e
        })
    }
}
