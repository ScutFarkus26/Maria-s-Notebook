import SwiftUI
import SwiftData

/// The main meeting session view showing student context and the meeting form side by side.
struct MeetingSessionView: View {
    let student: Student
    let allWorkModels: [WorkModel]
    let allLessonAssignments: [LessonAssignment]
    let lessons: [Lesson]
    let meetings: [StudentMeeting]
    let meetingTemplates: [MeetingTemplate]
    let workOverdueDays: Int
    var onComplete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var lastMeetingDate: Date? {
        meetings.first?.date
    }

    // MARK: - Work Stats (delegated to helper)

    private var workStats: MeetingWorkSnapshotHelper.WorkStats {
        MeetingWorkSnapshotHelper.computeWorkStats(
            for: student.id,
            allWorkModels: allWorkModels,
            workOverdueDays: workOverdueDays
        )
    }

    private var lessonsSinceLastMeeting: [LessonAssignment] {
        MeetingWorkSnapshotHelper.lessonsSinceLastMeeting(
            for: student.id,
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
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(
        firstName: "Alan", lastName: "Turing",
        birthday: Date(timeIntervalSince1970: 0), level: .upper
    )
    context.insert(student)

    return MeetingSessionView(
        student: student,
        allWorkModels: [],
        allLessonAssignments: [],
        lessons: [],
        meetings: [],
        meetingTemplates: [],
        workOverdueDays: 14
    )
    .previewEnvironment(using: container)
}
