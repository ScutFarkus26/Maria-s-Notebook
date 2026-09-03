import OSLog
import SwiftUI
import CoreData

// MARK: - Content Mode Sections

extension ProjectSessionDetailView {

    // MARK: - Choice Mode Content

    @ViewBuilder
    var choiceModeContent: some View {
        // Offered works section
        Section("Offered Follow-Ups") {
            ForEach(offeredWorks, id: \.objectID) { work in
                offeredWorkRow(work)
            }

            Button {
                showAddWorkSheet = true
            } label: {
                Label("Add Follow-Up Offer", systemImage: "plus.circle.fill")
            }
        }

        // CDStudent selection status
        Section("Student Selections") {
            ForEach(projectMemberIDs.sorted { studentName(for: $0) < studentName(for: $1) }, id: \.self) { studentID in
                studentSelectionRow(studentID: studentID)
            }
        }
    }

    @ViewBuilder
    func offeredWorkRow(_ work: CDWorkModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(work.title.isEmpty ? "Untitled follow-up" : work.title)
                    .font(.headline)
                Spacer()
                let count = work.selectedStudentIDs.count
                Label("\(count) selected", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !work.latestUnifiedNoteText.isEmpty {
                Text(work.latestUnifiedNoteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let due = work.dueAt {
                Label {
                    Text(due, format: Date.FormatStyle().month().day())
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func studentSelectionRow(studentID: String) -> some View {
        let selectedWorks = sessionWorkModels.filter { work in
            ((work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []).contains { $0.studentID == studentID }
        }
        let count = selectedWorks.count
        let min = Int(session.minSelections)
        let isComplete = count >= min

        Button {
            showSelectionSheetForStudent = studentID
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName(for: studentID))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !selectedWorks.isEmpty {
                        Text(selectedWorks.map { $0.title.isEmpty ? "Untitled" : $0.title }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(count)/\(min)")
                        .font(.caption)
                        .foregroundStyle(isComplete ? .green : .orange)
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? .green : .orange)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Uniform Mode Content

    @ViewBuilder
    var uniformModeContent: some View {
        if groupedByStudent.isEmpty {
            ContentUnavailableView(
                "No Follow-Ups",
                systemImage: "doc.text",
                description: Text("No follow-up work is linked to this check-in.")
            )
        } else {
            ForEach(groupedByStudent, id: \.id) { bucket in
                Section(header: Text(studentName(for: bucket.id)).font(.headline)) {
                    ForEach(bucket.items, id: \.objectID) { work in
                        workRow(work)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func workRow(_ work: CDWorkModel) -> some View {
        ProjectWorkProgressRow(
            work: work,
            lesson: UUID(uuidString: work.lessonID).flatMap { lessonsByID[$0] },
            onChangeLesson: { showLessonPickerForWork = work },
            onEditStep: { step in editStep(for: work, step: step) },
            onSave: { reason in saveProjectSession(reason: reason) }
        )
    }
}

private struct ProjectWorkProgressRow: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @ObservedObject var work: CDWorkModel

    let lesson: CDLesson?
    let onChangeLesson: () -> Void
    let onEditStep: (CDWorkStep?) -> Void
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.small) {
                TextField("Follow-up", text: Binding(
                    get: { work.title },
                    set: { work.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { persist(reason: "Rename Project Follow-Up") }

                Picker("Progress", selection: Binding(
                    get: { work.status },
                    set: { updateStatus($0) }
                )) {
                    ForEach(WorkStatus.allCases) { status in
                        Label(status.displayName, systemImage: status.iconName).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack(spacing: 8) {
                if let lesson {
                    Label("Linked: \(lesson.name)", systemImage: SFSymbol.Education.bookClosed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label("No lesson linked", systemImage: SFSymbol.Education.bookClosed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onChangeLesson()
                } label: {
                    Label("Change Lesson", systemImage: "book")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            ProjectWorkNoteField(work: work, onSave: onSave)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                HStack {
                    Label("Steps", systemImage: "list.bullet.clipboard")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onEditStep(nil)
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                if work.orderedSteps.isEmpty {
                    Text("No steps yet")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(work.orderedSteps, id: \.objectID) { step in
                        ProjectStepInlineRow(
                            step: step,
                            onToggle: { toggleStep(step) },
                            onEdit: { onEditStep(step) }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .onDisappear { persist(reason: "Save Project Follow-Up") }
    }

    private func updateStatus(_ status: WorkStatus) {
        let wasComplete = work.status == .complete
        work.status = status
        work.lastTouchedAt = Date()

        if status == .complete, work.completedAt == nil {
            work.completedAt = Date()
        } else if wasComplete, status != .complete {
            work.completedAt = nil
        }

        persist(reason: "Update Project Progress")
    }

    private func toggleStep(_ step: CDWorkStep) {
        let service = CDWorkStepServiceImpl(context: modelContext)
        do {
            try service.toggleCompletion(step)
            persist(reason: "Update Project Step")
        } catch {
            Logger.projects.warning("Failed to toggle project step: \(error)")
        }
    }

    private func persist(reason: String) {
        work.lastTouchedAt = Date()
        onSave(reason)
    }
}

private struct ProjectWorkNoteField: View {
    @ObservedObject var work: CDWorkModel
    let onSave: (String) -> Void
    @Environment(\.managedObjectContext) private var modelContext
    @State private var text: String

    init(work: CDWorkModel, onSave: @escaping (String) -> Void) {
        self.work = work
        self.onSave = onSave
        text = work.latestUnifiedNoteText
    }

    var body: some View {
        TextField("Observation, question, or next step", text: $text, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            .onSubmit { persist() }
            .onDisappear { persist() }
    }

    private func persist() {
        let trimmed = text.trimmed()
        guard trimmed != work.latestUnifiedNoteText.trimmed() else { return }
        work.setLegacyNoteText(trimmed.isEmpty ? nil : trimmed, in: modelContext)
        work.lastTouchedAt = Date()
        onSave("Save Project Observation")
    }
}

private struct ProjectStepInlineRow: View {
    @ObservedObject var step: CDWorkStep
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Button(action: onToggle) {
                Image(systemName: step.iconName)
                    .foregroundStyle(step.statusColor)
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(step.title.isEmpty ? "Untitled step" : step.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .strikethrough(step.isCompleted)
                    .foregroundStyle(step.isCompleted ? .secondary : .primary)
                if !step.instructions.isEmpty {
                    Text(step.instructions)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !step.notes.isEmpty {
                    Text(step.notes)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}
