import OSLog
import SwiftUI
import CoreData

/// Quick entry form for recording a practice observation
/// Optimized workflow: observe -> add partner -> note -> schedule check-in
struct QuickPracticeSessionSheet: View {
    static let logger = Logger.work

    let workItem: CDWorkModel
    var onSave: ((CDPracticeSession) -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var modelContext

    @FetchRequest(sortDescriptors: []) private var allStudentsRaw: FetchedResults<CDStudent>
    private var allStudents: [CDStudent] { allStudentsRaw.filterEnrolled() }
    @FetchRequest(sortDescriptors: []) private var allWork: FetchedResults<CDWorkModel>
    @FetchRequest(sortDescriptors: []) private var allLessonAssignments: FetchedResults<CDLessonAssignment>

    // Session basics
    @State var sessionDate: Date = Date()
    @State var hasDuration: Bool = false
    @State var durationMinutes: Int = 20

    // Quick partner selection
    @State var selectedPartnerIDs: Set<UUID> = []
    @State var showPartnerSelector: Bool = false

    // Quality metrics (quick tap)
    @State var practiceQuality: Int?
    @State var independenceLevel: Int?

    // Observable behaviors (checkboxes)
    @State var askedForHelp: Bool = false
    @State var helpedPeer: Bool = false
    @State var struggledWithConcept: Bool = false
    @State var madeBreakthrough: Bool = false
    @State var needsReteaching: Bool = false
    @State var readyForCheckIn: Bool = false
    @State var readyForAssessment: Bool = false

    // Next steps
    @State var scheduleCheckIn: Bool = false
    @State var checkInDate: Date = Date().addingTimeInterval(24 * 60 * 60) // Tomorrow
    @State var followUpActions: String = ""
    @State var materialsUsed: String = ""

    // Notes
    @State var sessionNotes: String = ""

    var repository: PracticeSessionRepository {
        PracticeSessionRepository(context: modelContext)
    }

    private var studentForWork: CDStudent? {
        guard let studentID = UUID(uuidString: workItem.studentID) else { return nil }
        return allStudents.first { $0.id == studentID }
    }

    // Co-learners for this work item (suggested partners)
    var suggestedPartners: [CDStudent] {
        guard let lessonUUID = UUID(uuidString: workItem.lessonID),
              let studentUUID = UUID(uuidString: workItem.studentID) else {
            return []
        }

        // Find co-learners from CDLessonAssignment
        let lessonAssignment = allLessonAssignments.first { la in
            la.lessonIDUUID == lessonUUID &&
            la.studentUUIDs.contains(studentUUID)
        }

        guard let coLearnerIDs = lessonAssignment?.studentUUIDs else {
            return []
        }

        return allStudents
            .filter { student in
                guard let sid = student.id else { return false }
                return coLearnerIDs.contains(sid) && sid != studentUUID
            }
            .sorted { $0.firstName < $1.firstName }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header with student info
                        headerSection

                        Divider()

                        // Quick duration presets
                        durationSection

                        Divider()

                        // Partner selection (optional)
                        partnerSection

                        Divider()

                        // Quick quality metrics
                        qualityMetricsSection

                        Divider()

                        // Observable behaviors (checkboxes)
                        behaviorsSection

                        Divider()

                        // Notes
                        notesSection

                        Divider()

                        // Next steps (optional)
                        nextStepsSection
                    }
                    .padding(24)
                }

                Divider()

                // Bottom bar
                bottomBar
            }
            .navigationTitle("Quick Practice Entry")
            .inlineNavigationTitle()
        }
    }

    // MARK: - View Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((workItem.kind ?? .practiceLesson).color.opacity(UIConstants.OpacityConstants.accent))
                        .frame(width: 44, height: 44)

                    Image(systemName: (workItem.kind ?? .practiceLesson).iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle((workItem.kind ?? .practiceLesson).color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let student = studentForWork {
                        Text(StudentFormatter.displayName(for: student))
                            .font(AppTheme.ScaledFont.titleSmall)
                    }

                    Text(workItem.title)
                        .font(AppTheme.ScaledFont.body)
                        .foregroundStyle(.secondary)
                }
            }

            DatePicker("Practice Date", selection: $sessionDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(AppTheme.ScaledFont.body)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDuration) {
                Text("CDTrackEntity Duration")
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }

            if hasDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([10, 15, 20, 30], id: \.self) { minutes in
                            Button {
                                durationMinutes = minutes
                            } label: {
                                Text("\(minutes) min")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(durationMinutes == minutes ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(
                                                durationMinutes == minutes
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(UIConstants.OpacityConstants.light)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Stepper("Custom: \(durationMinutes) min", value: $durationMinutes, in: 5...120, step: 5)
                        .font(AppTheme.ScaledFont.body)
                }
                .padding(.leading, 24)
            }
        }
    }
}
