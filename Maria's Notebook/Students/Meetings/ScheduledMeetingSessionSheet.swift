// ScheduledMeetingSessionSheet.swift
// Wrapper that loads queries for MeetingSessionView from a student UUID.

import SwiftUI
import SwiftData

/// Sheet presented when starting a scheduled meeting from TodayView.
/// Fetches all required data via @Query and delegates to MeetingSessionView.
struct ScheduledMeetingSessionSheet: View {
    let studentID: UUID
    var onComplete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    @Query(sort: Student.sortByName) private var allStudents: [Student]

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]

    @Query(sort: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)])
    private var allLessonAssignments: [LessonAssignment]

    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var lessons: [Lesson]

    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var allMeetings: [StudentMeeting]

    @Query(sort: [SortDescriptor(\MeetingTemplate.sortOrder)])
    private var meetingTemplates: [MeetingTemplate]

    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = WorkAgeDefaults.overdueDays

    private var student: Student? {
        allStudents.first { $0.id == studentID }
    }

    private var meetingsForStudent: [StudentMeeting] {
        allMeetings.filter { $0.studentIDUUID == studentID }
    }

    var body: some View {
        NavigationStack {
            if let student {
                MeetingSessionView(
                    student: student,
                    allWorkModels: allWorkModels,
                    allLessonAssignments: allLessonAssignments,
                    lessons: lessons,
                    meetings: meetingsForStudent,
                    meetingTemplates: meetingTemplates,
                    workOverdueDays: workOverdueDays,
                    onComplete: onComplete
                )
                .navigationTitle("Meeting – \(student.firstName)")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            } else {
                ContentUnavailableView(
                    "Student Not Found",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
        }
    }
}
