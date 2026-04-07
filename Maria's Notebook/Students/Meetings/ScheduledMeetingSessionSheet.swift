// ScheduledMeetingSessionSheet.swift
// Wrapper that loads queries for MeetingSessionView from a student UUID.

import SwiftUI
import CoreData

/// Sheet presented when starting a scheduled meeting from TodayView.
/// Fetches all required data via @Query and delegates to MeetingSessionView.
struct ScheduledMeetingSessionSheet: View {
    let studentID: UUID
    var onComplete: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true), NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)]) private var allStudents: FetchedResults<CDStudent>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)])
    private var allWorkModels: FetchedResults<CDWorkModel>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)])
    private var allLessonAssignments: FetchedResults<CDLessonAssignment>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var lessons: FetchedResults<CDLesson>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)])
    private var allMeetings: FetchedResults<CDStudentMeeting>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDMeetingTemplate.sortOrder, ascending: true)])
    private var meetingTemplates: FetchedResults<CDMeetingTemplate>

    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = WorkAgeDefaults.overdueDays

    private var student: CDStudent? {
        allStudents.first { $0.id == studentID }
    }

    private var meetingsForStudent: [CDStudentMeeting] {
        allMeetings.filter { $0.studentIDUUID == studentID }
    }

    var body: some View {
        NavigationStack {
            if let student {
                MeetingSessionView(
                    student: student,
                    allWorkModels: Array(allWorkModels),
                    allLessonAssignments: Array(allLessonAssignments),
                    lessons: Array(lessons),
                    meetings: meetingsForStudent,
                    meetingTemplates: Array(meetingTemplates),
                    workOverdueDays: workOverdueDays,
                    onComplete: onComplete
                )
                .navigationTitle("Meeting – \(student.firstName)")
                .inlineNavigationTitle()
            } else {
                ContentUnavailableView(
                    "Student Not Found",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
            }
        }
    }
}
