// ScheduledMeetingSessionSheet.swift
// A child's meeting opened from Today, the student record, or its own Mac window.

import SwiftUI
import CoreData

/// Sheet presented when starting a scheduled meeting from TodayView.
/// The session fetches its own child's data (`MeetingSessionView`).
struct ScheduledMeetingSessionSheet: View {
    let studentID: UUID
    var onComplete: (() -> Void)?

    @Environment(\.dependencies) private var dependencies

    private var student: CDStudent? {
        dependencies.roster.student(id: studentID)
    }

    var body: some View {
        NavigationStack {
            if let student {
                MeetingSessionView(
                    student: student,
                    actions: MeetingSessionActions(completeLabel: "Complete Meeting", onComplete: onComplete)
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
