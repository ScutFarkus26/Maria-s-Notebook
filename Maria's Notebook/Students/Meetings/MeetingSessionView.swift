import SwiftUI
import CoreData

/// The main meeting session view showing student context and the meeting form side by side.
struct MeetingSessionView: View {
    let student: CDStudent
    let allWorkModels: [CDWorkModel]
    let allLessonAssignments: [CDLessonAssignment]
    let lessons: [CDLesson]
    let meetings: [CDStudentMeeting]
    let meetingTemplates: [CDMeetingTemplate]
    let workOverdueDays: Int
    var onComplete: (() -> Void)?

    @Environment(\.managedObjectContext) private var viewContext

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: CDLesson] {
        Dictionary(lessons.compactMap { lesson -> (UUID, CDLesson)? in
            guard let id = lesson.id else { return nil }
            return (id, lesson)
        }, uniquingKeysWith: { first, _ in first })
    }

    private var lastMeetingDate: Date? {
        meetings.first?.date
    }

    // MARK: - Work Stats (delegated to helper)

    private var workStats: MeetingWorkSnapshotHelper.WorkStats {
        guard let studentID = student.id else {
            return MeetingWorkSnapshotHelper.WorkStats(open: [], overdue: [], recentCompleted: [])
        }
        return MeetingWorkSnapshotHelper.computeWorkStats(
            for: studentID,
            allWorkModels: allWorkModels,
            workOverdueDays: workOverdueDays
        )
    }

    private var lessonsSinceLastMeeting: [CDLessonAssignment] {
        guard let studentID = student.id else { return [] }
        return MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: studentID,
            lastMeetingDate: lastMeetingDate,
            allLessonAssignments: allLessonAssignments
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > 900

            if isWide {
                // Side-by-side layout for wide screens
                HStack(spacing: 0) {
                    // Context pane (left)
                    MeetingContextPane(
                        student: student,
                        openWork: workStats.open,
                        overdueWork: workStats.overdue,
                        recentCompleted: workStats.recentCompleted,
                        lessonsSinceLastMeeting: lessonsSinceLastMeeting,
                        meetings: meetings,
                        lessonsByID: lessonsByID
                    )
                    .frame(width: min(geometry.size.width * 0.4, 400))
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))

                    Divider()

                    // Meeting form (right)
                    MeetingFormPane(
                        student: student,
                        meetings: meetings,
                        meetingTemplates: meetingTemplates,
                        onComplete: onComplete
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Stacked layout for narrow screens
                ScrollView {
                    VStack(spacing: 24) {
                        // Context section (collapsible)
                        MeetingContextPane(
                            student: student,
                            openWork: workStats.open,
                            overdueWork: workStats.overdue,
                            recentCompleted: workStats.recentCompleted,
                            lessonsSinceLastMeeting: lessonsSinceLastMeeting,
                            meetings: meetings,
                            lessonsByID: lessonsByID,
                            isCompact: true
                        )

                        Divider()

                        // Meeting form
                        MeetingFormPane(
                            student: student,
                            meetings: meetings,
                            meetingTemplates: meetingTemplates,
                            onComplete: onComplete
                        )
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(StudentFormatter.displayName(for: student))
        .inlineNavigationTitle()
    }
}

// MARK: - Preview

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let student = Student(context: ctx)
    student.firstName = "Alan"
    student.lastName = "Turing"
    student.birthday = Date(timeIntervalSince1970: 0)
    student.level = .upper

    return MeetingSessionView(
        student: student,
        allWorkModels: [],
        allLessonAssignments: [],
        lessons: [],
        meetings: [],
        meetingTemplates: [],
        workOverdueDays: 14
    )
    .previewEnvironment(using: stack)
}
