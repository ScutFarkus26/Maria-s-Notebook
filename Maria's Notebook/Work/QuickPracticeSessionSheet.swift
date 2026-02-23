import SwiftUI
import SwiftData

/// Quick entry form for recording a practice observation
/// Optimized workflow: observe → add partner → note → schedule check-in
struct QuickPracticeSessionSheet: View {
    let workItem: WorkModel
    var onSave: ((PracticeSession) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allStudents: [Student]
    @Query private var allWork: [WorkModel]
    @Query private var allLessonAssignments: [LessonAssignment]

    // Session basics
    @State private var sessionDate: Date = Date()
    @State private var hasDuration: Bool = false
    @State private var durationMinutes: Int = 20

    // Quick partner selection
    @State private var selectedPartnerIDs: Set<UUID> = []
    @State private var showPartnerSelector: Bool = false

    // Quality metrics (quick tap)
    @State private var practiceQuality: Int? = nil
    @State private var independenceLevel: Int? = nil

    // Observable behaviors (checkboxes)
    @State private var askedForHelp: Bool = false
    @State private var helpedPeer: Bool = false
    @State private var struggledWithConcept: Bool = false
    @State private var madeBreakthrough: Bool = false
    @State private var needsReteaching: Bool = false
    @State private var readyForCheckIn: Bool = false
    @State private var readyForAssessment: Bool = false

    // Next steps
    @State private var scheduleCheckIn: Bool = false
    @State private var checkInDate: Date = Date().addingTimeInterval(24 * 60 * 60) // Tomorrow
    @State private var followUpActions: String = ""
    @State private var materialsUsed: String = ""

    // Notes
    @State private var sessionNotes: String = ""

    private var repository: PracticeSessionRepository {
        PracticeSessionRepository(modelContext: modelContext)
    }

    private var studentForWork: Student? {
        guard let studentID = UUID(uuidString: workItem.studentID) else { return nil }
        return allStudents.first { $0.id == studentID }
    }

    // Co-learners for this work item (suggested partners)
    private var suggestedPartners: [Student] {
        guard let lessonUUID = UUID(uuidString: workItem.lessonID),
              let studentUUID = UUID(uuidString: workItem.studentID) else {
            return []
        }

        // Find co-learners from LessonAssignment
        let lessonAssignment = allLessonAssignments.first { la in
            la.lessonIDUUID == lessonUUID &&
            la.studentUUIDs.contains(studentUUID)
        }

        guard let coLearnerIDs = lessonAssignment?.studentUUIDs else {
            return []
        }

        return allStudents
            .filter { coLearnerIDs.contains($0.id) && $0.id != studentUUID }
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - View Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((workItem.kind ?? .practiceLesson).color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: (workItem.kind ?? .practiceLesson).iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle((workItem.kind ?? .practiceLesson).color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let student = studentForWork {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                    }

                    Text(workItem.title)
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            DatePicker("Practice Date", selection: $sessionDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDuration) {
                Text("Track Duration")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
            }

            if hasDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([10, 15, 20, 30], id: \.self) { minutes in
                            Button {
                                durationMinutes = minutes
                            } label: {
                                Text("\(minutes) min")
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                    .foregroundStyle(durationMinutes == minutes ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(durationMinutes == minutes ? Color.accentColor : Color.primary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Stepper("Custom: \(durationMinutes) min", value: $durationMinutes, in: 5...120, step: 5)
                        .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                }
                .padding(.leading, 24)
            }
        }
    }

    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    showPartnerSelector.toggle()
                }
            } label: {
                HStack {
                    Text("Practice Partners")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("(Optional)")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !selectedPartnerIDs.isEmpty {
                        Text("\(selectedPartnerIDs.count)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor))
                    }

                    Image(systemName: showPartnerSelector ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showPartnerSelector {
                if suggestedPartners.isEmpty {
                    Text("No co-learners found")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(suggestedPartners) { partner in
                        partnerRow(for: partner)
                    }
                }
            }
        }
    }

    private func partnerRow(for student: Student) -> some View {
        Button {
            if selectedPartnerIDs.contains(student.id) {
                selectedPartnerIDs.remove(student.id)
            } else {
                selectedPartnerIDs.insert(student.id)
            }
        } label: {
            HStack {
                Image(systemName: selectedPartnerIDs.contains(student.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedPartnerIDs.contains(student.id) ? .blue : .secondary)
                    .font(.system(size: 20))

                Text(StudentFormatter.displayName(for: student))
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPartnerIDs.contains(student.id) ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality Metrics")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))

            // Practice Quality
            VStack(alignment: .leading, spacing: 8) {
                Text("Practice Quality")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: practiceQuality, color: .blue) {
                            practiceQuality = level
                        }
                    }

                    Spacer()

                    if let quality = practiceQuality {
                        Text(qualityLabel(for: quality))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Independence Level
            VStack(alignment: .leading, spacing: 8) {
                Text("Independence Level")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: independenceLevel, color: .green) {
                            independenceLevel = level
                        }
                    }

                    Spacer()

                    if let independence = independenceLevel {
                        Text(independenceLabel(for: independence))
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func qualityCircle(level: Int, selected: Int?, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.opacity((selected ?? 0) >= level ? 1.0 : 0.2))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var behaviorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observable Behaviors")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))

            VStack(spacing: 8) {
                behaviorToggle("Asked for help", isOn: $askedForHelp, icon: "hand.raised.fill", color: .orange)
                behaviorToggle("Helped a peer", isOn: $helpedPeer, icon: "hands.sparkles.fill", color: .green)
                behaviorToggle("Struggled with concept", isOn: $struggledWithConcept, icon: "exclamationmark.triangle.fill", color: .red)
                behaviorToggle("Made breakthrough", isOn: $madeBreakthrough, icon: "lightbulb.fill", color: .yellow)
                behaviorToggle("Needs reteaching", isOn: $needsReteaching, icon: "arrow.counterclockwise.circle.fill", color: .purple)
                behaviorToggle("Ready for check-in", isOn: $readyForCheckIn, icon: "checkmark.circle.fill", color: .blue)
                behaviorToggle("Ready for assessment", isOn: $readyForAssessment, icon: "checkmark.seal.fill", color: .indigo)
            }
        }
    }

    private func behaviorToggle(_ label: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary)

                Text(label)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
            }
        }
        .toggleStyle(.switch)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Notes")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))

            TextEditor(text: $sessionNotes)
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .frame(minHeight: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private var nextStepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Steps")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            // Schedule check-in
            Toggle(isOn: $scheduleCheckIn) {
                Text("Schedule Check-in")
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
            }

            if scheduleCheckIn {
                DatePicker("Check-in Date", selection: $checkInDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .padding(.leading, 24)
            }

            // Follow-up actions
            VStack(alignment: .leading, spacing: 6) {
                Text("Follow-up Actions")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("e.g., 'Reteach borrowing', 'Create scaffolded worksheet'", text: $followUpActions, axis: .vertical)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .lineLimit(2...4)
            }

            // Materials used
            VStack(alignment: .leading, spacing: 6) {
                Text("Materials Used")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("e.g., 'Manipulatives', 'Worksheet pg 12'", text: $materialsUsed)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                saveSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Helper Functions

    private func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    private func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
        }
    }

    @MainActor
    private func saveSession() {
        // Build student IDs list
        var studentIDs = [workItem.studentID]
        studentIDs.append(contentsOf: selectedPartnerIDs.map { $0.uuidString })

        // Create practice session
        let session = repository.create(
            date: sessionDate,
            duration: hasDuration ? TimeInterval(durationMinutes * 60) : nil,
            studentIDs: studentIDs.map { UUID(uuidString: $0)! },
            workItemIDs: [UUID(uuidString: workItem.id.uuidString)!],
            sharedNotes: sessionNotes,
            location: nil
        )

        // Set quality metrics
        session.practiceQuality = practiceQuality
        session.independenceLevel = independenceLevel

        // Set behavior flags
        session.askedForHelp = askedForHelp
        session.helpedPeer = helpedPeer
        session.struggledWithConcept = struggledWithConcept
        session.madeBreakthrough = madeBreakthrough
        session.needsReteaching = needsReteaching
        session.readyForCheckIn = readyForCheckIn
        session.readyForAssessment = readyForAssessment

        // Set next steps
        if scheduleCheckIn {
            session.checkInScheduledFor = checkInDate
        }
        session.followUpActions = followUpActions
        session.materialsUsed = materialsUsed

        do {
            try modelContext.save()
        } catch {
            print("⚠️ [saveSession] Failed to save quick practice session: \(error)")
        }

        onSave?(session)
        dismiss()
    }
}
