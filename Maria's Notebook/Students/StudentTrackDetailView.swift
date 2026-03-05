import OSLog
import SwiftUI
import SwiftData

struct StudentTrackDetailView: View {
    private static let logger = Logger.students

    let enrollment: StudentTrackEnrollment
    let track: Track

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Pre-computed data loaded on appear for better performance
    @State private var trackLessons: [Lesson] = []
    @State private var proficientLessonIDs: Set<String> = []
    @State private var presentedLessonIDs: Set<String> = []
    @State private var isLoaded = false

    private var proficientCount: Int { proficientLessonIDs.count }
    private var totalLessons: Int { trackLessons.count }

    private var progressPercent: Int {
        guard totalLessons > 0 else { return 0 }
        return Int((Double(proficientCount) / Double(totalLessons)) * 100)
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

                        // Lessons list
                        lessonsSection
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        let studentID = enrollment.studentID

        // Fetch lessons for this subject/group
        let allLessons: [Lesson]
        do {
            allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
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
        let lessonIDStrings = Set(trackLessons.map { $0.id.uuidString })
        let allPresentations: [LessonPresentation]
        do {
            allPresentations = try modelContext.fetch(FetchDescriptor<LessonPresentation>())
        } catch {
            Self.logger.warning("Failed to fetch LessonPresentations: \(error)")
            allPresentations = []
        }
        let studentPresentations = allPresentations.filter { lp in
            lp.studentID == studentID && lessonIDStrings.contains(lp.lessonID)
        }

        presentedLessonIDs = Set(studentPresentations.map { $0.lessonID })
        proficientLessonIDs = Set(studentPresentations.filter { $0.state == .proficient }.map { $0.lessonID })

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
                            colors: [.yellow.opacity(0.3), .yellow.opacity(0.05), .clear],
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
                    Text("Started \(Self.dateFormatter.string(from: startedAt))")
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
                        colors: [.yellow.opacity(0.1), .orange.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.yellow.opacity(0.3), .orange.opacity(0.2)],
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
                    .stroke(Color.green.opacity(0.15), lineWidth: 12)
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
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Lessons Section

    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.circle.fill")
                    .foregroundStyle(.blue)
                Text("Lessons")
                    .font(.headline)
            }

            if trackLessons.isEmpty {
                emptyLessonsView
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(trackLessons.enumerated()), id: \.element.id) { index, lesson in
                        lessonRow(lesson: lesson, index: index + 1)
                    }
                }
            }
        }
    }

    private var emptyLessonsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No lessons found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func lessonRow(lesson: Lesson, index: Int) -> some View {
        let lessonID = lesson.id.uuidString
        let isProficient = proficientLessonIDs.contains(lessonID)
        let isPresented = presentedLessonIDs.contains(lessonID)

        return HStack(spacing: 12) {
            // Step number or checkmark
            ZStack {
                Circle()
                    .fill(
                        isProficient ? Color.green
                            : (isPresented ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
                    .frame(width: 32, height: 32)

                if isProficient {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.caption.bold())
                        .foregroundStyle(isPresented ? .orange : .secondary)
                }
            }

            // Lesson name
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(.subheadline)
                    .fontWeight(isProficient ? .medium : .regular)
                    .foregroundStyle(isProficient ? .primary : .secondary)

                if isProficient {
                    Label("Mastered", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.success)
                } else if isPresented {
                    Label("In Progress", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                }
            }

            Spacer()

            // Status indicator
            if isProficient {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isProficient ? Color.green.opacity(0.08) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isProficient ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let track = Track(title: "Math — Fundamentals")
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(), level: .upper)
    let enrollment = StudentTrackEnrollment(
        studentID: student.id.uuidString,
        trackID: track.id.uuidString,
        startedAt: Date(),
        isActive: false
    )
    context.insert(track)
    context.insert(student)
    context.insert(enrollment)
    return StudentTrackDetailView(enrollment: enrollment, track: track)
        .previewEnvironment(using: container)
}
