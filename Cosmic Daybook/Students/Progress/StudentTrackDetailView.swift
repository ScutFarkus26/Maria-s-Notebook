import SwiftUI
import CoreData

/// One child on one lesson sequence: her progress ring and the timeline of
/// its lessons. Opened from a Current Learning card or a finished sequence
/// in Past Learning; the standing is re-read from the store on open.
struct StudentTrackDetailView: View {
    let student: CDStudent
    /// The standing the card was built from; the sheet reloads it on open.
    let standing: SequenceStanding

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Pre-computed data loaded on appear for better performance
    @State private var loaded: SequenceStanding?
    @State private var isLoaded = false

    // Timeline data from StudentAreaProgressionViewModel
    @State private var progressionVM = StudentAreaProgressionViewModel()

    private var current: SequenceStanding { loaded ?? standing }
    private var proficientCount: Int { current.masteredCount }
    private var totalLessons: Int { current.total }

    private var progressPercent: Int {
        guard totalLessons > 0 else { return 0 }
        return Int((Double(proficientCount) / Double(totalLessons)) * 100)
    }

    private var areaColor: Color {
        AppColors.color(forArea: standing.area)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoaded {
                    VStack(alignment: .leading, spacing: 24) {
                        // Celebration header for a finished sequence
                        if current.isFinished {
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
            .navigationTitle(standing.title)
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
        let load = StudentTrackDetailLoader.load(
            student: student, area: standing.area, sequence: standing.sequence, context: viewContext
        )
        loaded = load.standing

        // Load timeline via progression VM
        progressionVM.configure(for: student, area: standing.area, sequence: standing.sequence, context: viewContext)

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
                            colors: [
                                .yellow.opacity(UIConstants.OpacityConstants.semi),
                                .yellow.opacity(UIConstants.OpacityConstants.hint),
                                .clear
                            ],
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
                Text("Every lesson mastered!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let startedAt = current.firstGivenAt {
                    Text("Started \(DateFormatters.mediumDate.string(from: startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .surface(
            UIConstants.CornerRadius.hero,
            fill: LinearGradient(
                colors: [
                    .yellow.opacity(UIConstants.OpacityConstants.light),
                    .orange.opacity(UIConstants.OpacityConstants.hint)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            style: .continuous
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.hero)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .yellow.opacity(UIConstants.OpacityConstants.semi),
                            .orange.opacity(UIConstants.OpacityConstants.moderate)
                        ],
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
        .capsuleFill(color.opacity(UIConstants.OpacityConstants.light))
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "timeline.selection")
                    .foregroundStyle(areaColor)
                Text("Timeline")
                    .font(.headline)

                Spacer()

                Text("\(progressionVM.completedCount)/\(progressionVM.totalCount)")
                    .font(.subheadline.bold())
                    .foregroundStyle(areaColor)
            }

            if progressionVM.nodes.isEmpty {
                emptyTimelineView
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(progressionVM.nodes) { node in
                        ProgressionLessonRow(
                            node: node,
                            areaColor: areaColor,
                            // Not for a child who has left the class (bug hunt 2026-11-03 #32).
                            onScheduleLesson: node.isNext && progressionVM.canPlanLessons ? {
                                planLesson(node)
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

    /// Plans the lesson on the row tapped (the next one for the child), not the one after it.
    private func planLesson(_ node: LessonProgressionNode) {
        if let refusal = progressionVM.planLesson(node.lesson, context: viewContext) {
            ToastService.shared.showError(refusal)
        }
        progressionVM.configure(for: student, area: standing.area, sequence: standing.sequence, context: viewContext)
    }

}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct StudentTrackDetailViewPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext

        let student = CDStudent(context: ctx)
        student.firstName = "Alan"
        student.lastName = "Turing"
        student.birthday = Date()
        student.level = .upper

        let lesson = CDLesson(context: ctx)
        lesson.name = "Golden Beads"
        lesson.area = "Math"
        lesson.sequence = "Fundamentals"
        let standing = SequenceStanding(
            area: "Math", sequence: "Fundamentals", lessons: [lesson],
            givenLessonIDs: [lesson.id?.uuidString ?? ""], masteredLessonIDs: [lesson.id?.uuidString ?? ""],
            firstGivenAt: Date(), lastActivityAt: Date()
        )

        return StudentTrackDetailView(student: student, standing: standing)
            .previewEnvironment(using: stack)
    }
}

#Preview {
    StudentTrackDetailViewPreview()
}
