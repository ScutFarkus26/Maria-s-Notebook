import OSLog
import SwiftUI
import CoreData

// swiftlint:disable:next type_body_length
struct StudentTrackDetailView: View {
    private static let logger = Logger.students

    let enrollment: CDStudentTrackEnrollmentEntity
    let track: CDTrackEntity

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Pre-computed data loaded on appear for better performance
    @State private var trackLessons: [CDLesson] = []
    @State private var proficientLessonIDs: Set<String> = []
    @State private var presentedLessonIDs: Set<String> = []
    @State private var isLoaded = false

    // Timeline data from StudentSubjectProgressionViewModel
    @State private var progressionVM = StudentSubjectProgressionViewModel()
    @State private var student: CDStudent?
    @State private var parsedSubject: String = ""
    @State private var parsedGroup: String = ""

    private var proficientCount: Int { proficientLessonIDs.count }
    private var totalLessons: Int { trackLessons.count }

    private var progressPercent: Int {
        guard totalLessons > 0 else { return 0 }
        return Int((Double(proficientCount) / Double(totalLessons)) * 100)
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: parsedSubject)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoaded {
                    VStack(alignment: .leading, spacing: 24) {
                        // Celebration header for completed tracks
                        if !enrollment.isActive {
                            completionCelebration
                        }

                        // Progress section
                        progressSection

                        // Timeline section
                        timelineSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                }
            }
            .navigationTitle(track.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                loadData()
            }
        }
    }

    private func loadData() {
        // Parse subject and group from track title (format: "Subject — Group")
        let parts = track.title.components(separatedBy: " — ")
        guard parts.count == 2 else {
            isLoaded = true
            return
        }

        let subject = parts[0].trimmingCharacters(in: .whitespaces)
        let group = parts[1].trimmingCharacters(in: .whitespaces)
        parsedSubject = subject
        parsedGroup = group
        let studentID = enrollment.studentID

        // Fetch the student
        let allStudents = viewContext.safeFetch(NSFetchRequest<CDStudent>(entityName: "Student"))
        student = allStudents.first { $0.cloudKitKey == studentID }

        // Fetch lessons for this subject/group
        let allLessons: [CDLesson]
        do {
            allLessons = try viewContext.fetch(NSFetchRequest<CDLesson>(entityName: "Lesson"))
        } catch {
            Self.logger.warning("Failed to fetch Lessons: \(error)")
            allLessons = []
        }
        trackLessons = allLessons
            .filter { lesson in
                lesson.subject.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(subject) == .orderedSame &&
                lesson.group.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(group) == .orderedSame
            }
            .sorted { $0.orderInGroup < $1.orderInGroup }

        // Fetch LessonPresentations for this student
        let lessonIDStrings = Set(trackLessons.compactMap { $0.id?.uuidString })
        let allPresentations: [CDLessonPresentation]
        do {
            allPresentations = try viewContext.fetch(NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation"))
        } catch {
            Self.logger.warning("Failed to fetch LessonPresentations: \(error)")
            allPresentations = []
        }
        let studentPresentations = allPresentations.filter { lp in
            lp.studentID == studentID && lessonIDStrings.contains(lp.lessonID)
        }

        presentedLessonIDs = Set(studentPresentations.map(\.lessonID))
        proficientLessonIDs = Set(studentPresentations.filter { $0.state == .proficient }.map(\.lessonID))

        // Load timeline via progression VM
        if let foundStudent = student {
            progressionVM.configure(for: foundStudent, subject: subject, group: group, context: viewContext)
        }

        isLoaded = true
    }

    // MARK: - Celebration Header

    private var completionCelebration: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.yellow.opacity(UIConstants.OpacityConstants.semi), .yellow.opacity(UIConstants.OpacityConstants.hint), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                // Trophy icon
                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 4) {
                Text("Track Completed!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let startedAt = enrollment.startedAt {
                    Text("Started \(DateFormatters.mediumDate.string(from: startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.yellow.opacity(UIConstants.OpacityConstants.light), .orange.opacity(UIConstants.OpacityConstants.hint)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.yellow.opacity(UIConstants.OpacityConstants.semi), .orange.opacity(UIConstants.OpacityConstants.moderate)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            // Big progress ring
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.green.opacity(UIConstants.OpacityConstants.accent), lineWidth: 12)
                    .frame(width: 100, height: 100)

                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(proficientCount) / CGFloat(max(totalLessons, 1)))
                    .stroke(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                // Center text
                VStack(spacing: 0) {
                    Text("\(progressPercent)")
                        .font(AppTheme.ScaledFont.titleXLarge)
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats row
            HStack(spacing: 24) {
                statPill(
                    icon: "checkmark.circle.fill",
                    value: "\(proficientCount)",
                    label: "Mastered",
                    color: .green
                )

                statPill(
                    icon: "book.fill",
                    value: "\(totalLessons)",
                    label: "Total",
                    color: .blue
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(color.opacity(UIConstants.OpacityConstants.light))
        )
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "timeline.selection")
                    .foregroundStyle(subjectColor)
                Text("Timeline")
                    .font(.headline)

                Spacer()

                Text("\(progressionVM.completedCount)/\(progressionVM.totalCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(subjectColor)
            }

            if progressionVM.nodes.isEmpty {
                emptyTimelineView
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(progressionVM.nodes) { node in
                        ProgressionLessonRow(
                            node: node,
                            subjectColor: subjectColor,
                            onScheduleLesson: node.isNext ? {
                                scheduleNextLesson(after: node)
                            } : nil
                        )
                    }
                }
            }
        }
    }

    private var emptyTimelineView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(UIConstants.OpacityConstants.half))

            Text("No lessons found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func scheduleNextLesson(after node: LessonProgressionNode) {
        progressionVM.scheduleNextLesson(after: node.lesson, context: viewContext)
        if let foundStudent = student {
            progressionVM.configure(
                for: foundStudent, subject: parsedSubject, group: parsedGroup, context: viewContext
            )
        }
    }

}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let track = CDTrackEntity(context: ctx)
    track.title = "Math — Fundamentals"

    let student = CDStudent(context: ctx)
    student.firstName = "Alan"
    student.lastName = "Turing"
    student.birthday = Date()
    student.level = .upper

    let enrollment = CDStudentTrackEnrollmentEntity(context: ctx)
    enrollment.studentID = student.id?.uuidString ?? ""
    enrollment.trackID = track.id?.uuidString ?? ""
    enrollment.student = student
    enrollment.track = track
    enrollment.startedAt = Date()
    enrollment.isActive = false

    return StudentTrackDetailView(enrollment: enrollment, track: track)
        .previewEnvironment(using: stack)
}
