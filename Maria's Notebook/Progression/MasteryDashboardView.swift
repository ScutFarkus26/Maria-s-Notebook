import SwiftUI
import SwiftData

/// Aggregate mastery dashboard showing student progress across a curriculum track.
/// Displays a matrix of students × track steps with mastery state color indicators.
struct MasteryDashboardView: View {
    let track: Track
    @Environment(\.modelContext) private var modelContext
    @State private var studentRows: [MasteryStudentRow] = []
    @State private var steps: [TrackStep] = []
    @State private var isLoading = true

    private let cellSize: CGFloat = 36
    private let nameColumnWidth: CGFloat = 140

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading mastery data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if studentRows.isEmpty {
                ContentUnavailableView("No enrolled students", systemImage: "person.3")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    summaryBar
                    matrixView
                }
                .padding()
            }
        }
        .navigationTitle("Mastery: \(track.title.isEmpty ? "Track" : track.title)")
        .inlineNavigationTitle()
        .onAppear { loadData() }
    }

    // MARK: - Summary Stats

    private var summaryBar: some View {
        let allStates = studentRows.flatMap(\.stepStates)
        let total = max(allStates.count, 1)
        let proficient = allStates.filter { $0 == .proficient }.count
        let practicing = allStates.filter { $0 == .practicing }.count
        let presented = allStates.filter { $0 == .presented }.count
        let notStarted = allStates.filter { $0 == .notStarted }.count

        return HStack(spacing: 16) {
            statPill("Mastered", count: proficient, total: total, color: .green)
            statPill("Practicing", count: practicing, total: total, color: .blue)
            statPill("Presented", count: presented, total: total, color: .orange)
            statPill("Not Started", count: notStarted, total: total, color: .gray)
        }
    }

    private func statPill(_ label: String, count: Int, total: Int, color: Color) -> some View {
        let pct = Int(Double(count) / Double(total) * 100)
        return VStack(spacing: 2) {
            Text("\(pct)%")
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(pct) percent, \(count) of \(total)")
    }

    // MARK: - Matrix

    private var matrixView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 2) {
                // Header row with step names
                HStack(spacing: 2) {
                    Text("Student")
                        .font(.caption.bold())
                        .frame(width: nameColumnWidth, alignment: .leading)
                    ForEach(steps) { step in
                        Text(stepName(for: step))
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: cellSize)
                            .rotationEffect(.degrees(-45), anchor: .bottomLeading)
                            .frame(height: 60)
                    }
                }

                Divider()

                // Student rows
                ForEach(studentRows) { row in
                    HStack(spacing: 2) {
                        Text(row.studentName)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(width: nameColumnWidth, alignment: .leading)
                        ForEach(Array(row.stepStates.enumerated()), id: \.offset) { _, state in
                            Circle()
                                .fill(state.color)
                                .frame(width: 12, height: 12)
                                .frame(width: cellSize, height: cellSize)
                                .accessibilityLabel(state.label)
                        }
                    }
                }
            }
        }
    }

    private func stepName(for step: TrackStep) -> String {
        guard let lessonID = step.lessonTemplateID else {
            return "Step \(step.orderIndex + 1)"
        }
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate<Lesson> { $0.id == lessonID }
        )
        return modelContext.safeFetchFirst(descriptor)?.name ?? "Step \(step.orderIndex + 1)"
    }

    // MARK: - Data Loading

    private func loadData() {
        let sortedSteps = (track.steps ?? []).sorted(by: { $0.orderIndex < $1.orderIndex })
        self.steps = sortedSteps

        let trackID = track.id.uuidString
        let enrollments = modelContext.safeFetch(FetchDescriptor<StudentTrackEnrollment>())
            .filter { $0.trackID == trackID }

        let allStudents = modelContext.safeFetch(FetchDescriptor<Student>())
        let studentsByID = Dictionary(uniqueKeysWithValues: allStudents.map { ($0.id.uuidString, $0) })

        let allPresentations = modelContext.safeFetch(FetchDescriptor<LessonPresentation>())
        let presentationsByStudent = Dictionary(grouping: allPresentations) { $0.studentID }

        var rows: [MasteryStudentRow] = []
        for enrollment in enrollments {
            guard let student = studentsByID[enrollment.studentID] else { continue }
            let studentPresentations = presentationsByStudent[enrollment.studentID] ?? []
            let presentationByLesson = Dictionary(
                grouping: studentPresentations,
                by: { $0.lessonID }
            ).compactMapValues(\.last)

            var stepStates: [MasteryState] = []
            for step in sortedSteps {
                if let lessonID = step.lessonTemplateID {
                    if let pres = presentationByLesson[lessonID.uuidString] {
                        stepStates.append(MasteryState(from: pres.state))
                    } else {
                        stepStates.append(.notStarted)
                    }
                } else {
                    stepStates.append(.notStarted)
                }
            }

            rows.append(MasteryStudentRow(
                id: enrollment.id,
                studentName: student.fullName,
                stepStates: stepStates
            ))
        }

        self.studentRows = rows.sorted { $0.studentName < $1.studentName }
        self.isLoading = false
    }
}

// MARK: - Support Types

struct MasteryStudentRow: Identifiable {
    let id: UUID
    let studentName: String
    let stepStates: [MasteryState]
}

enum MasteryState {
    case notStarted, presented, practicing, readyForAssessment, proficient

    init(from state: LessonPresentationState) {
        switch state {
        case .presented: self = .presented
        case .practicing: self = .practicing
        case .readyForAssessment: self = .readyForAssessment
        case .proficient: self = .proficient
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .gray.opacity(UIConstants.OpacityConstants.semi)
        case .presented: return .orange
        case .practicing: return .blue
        case .readyForAssessment: return .yellow
        case .proficient: return .green
        }
    }

    var label: String {
        switch self {
        case .notStarted: return "Not Started"
        case .presented: return "Presented"
        case .practicing: return "Practicing"
        case .readyForAssessment: return "Ready for Assessment"
        case .proficient: return "Mastered"
        }
    }
}
