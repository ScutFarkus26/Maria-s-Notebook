import SwiftUI

// MARK: - Work Creation Panel

extension UnifiedPresentationWorkflowPanel {

    // MARK: - Work Creation Panel

    var workCreationPanel: some View {
        VStack(spacing: 0) {
            WorkflowPanelHeader(title: "Work Items")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bulkAssignmentSection

                    ForEach(sortedStudents, id: \.id) { student in
                        studentWorkSection(for: student)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Bulk Assignment Section

    var bulkAssignmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkflowSectionHeader(title: "Quick Assignment", icon: "doc.text.fill")

            HStack(spacing: 8) {
                TextField("Set same assignment for all students...", text: $presentationViewModel.bulkAssignment)
                    .textFieldStyle(.roundedBorder)

                Button("Apply") {
                    applyBulkAssignment()
                }
                .buttonStyle(.bordered)
                .disabled(presentationViewModel.bulkAssignment.trimmed().isEmpty)
            }

            // Default schedule toggles
            HStack(spacing: 16) {
                Toggle("Check-in", isOn: $presentationViewModel.defaultCheckInEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()

                if presentationViewModel.defaultCheckInEnabled {
                    DatePicker("", selection: $presentationViewModel.defaultCheckInDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Spacer()

                Toggle("Due", isOn: $presentationViewModel.defaultDueEnabled)
                    .toggleStyle(.switch)
                    .fixedSize()

                if presentationViewModel.defaultDueEnabled {
                    DatePicker("", selection: $presentationViewModel.defaultDueDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .font(.workflowCaption)

            // Check-in style picker (only meaningful when multiple students)
            if students.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check-In Style")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(CheckInStyle.allCases) { style in
                            SelectablePillButton(
                                item: style,
                                isSelected: bulkCheckInStyle == style,
                                color: style.color,
                                icon: style.iconName,
                                label: style.displayName
                            ) {
                                adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    bulkCheckInStyle = style
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    func applyBulkAssignment() {
        // Capture the trimmed text before calling the ViewModel (which clears bulkAssignment)
        var trimmed = presentationViewModel.bulkAssignment.trimmed()
        guard !trimmed.isEmpty else { return }

        // Auto-expand "Practice" to include the lesson name and set work kind
        var workKind: WorkKind = .followUpAssignment
        if trimmed.caseInsensitiveCompare("Practice") == .orderedSame {
            trimmed = "Practice: \(lessonName)"
            presentationViewModel.bulkAssignment = trimmed
            workKind = .practiceLesson
        }

        presentationViewModel.applyBulkAssignment()

        for student in students {
            // Check if this student already has work drafts
            if workDrafts[student.id]?.isEmpty ?? true {
                let draft = createWorkDraft(for: student.id, title: trimmed, kind: workKind, applyDefaultDates: true)
                workDrafts[student.id, default: []].append(draft)
            } else {
                // Update existing first draft
                if let firstIndex = workDrafts[student.id]?.indices.first {
                    workDrafts[student.id]?[firstIndex].title = trimmed

                    // Apply default dates if enabled and not already set
                    if presentationViewModel.defaultCheckInEnabled
                        && workDrafts[student.id]?[firstIndex].checkInDate == nil {
                        workDrafts[student.id]?[firstIndex].checkInDate = presentationViewModel.defaultCheckInDate
                    }
                    if presentationViewModel.defaultDueEnabled && workDrafts[student.id]?[firstIndex].dueDate == nil {
                        workDrafts[student.id]?[firstIndex].dueDate = presentationViewModel.defaultDueDate
                    }
                }
            }
        }

        // Show confirmation toast
        adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
            bulkAppliedMessage = "Applied \"\(trimmed)\" to \(students.count) student\(students.count == 1 ? "" : "s")"
            showBulkAppliedToast = true
        }
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                // Sleep interrupted, dismiss toast anyway
            }
            adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }

    // MARK: - Student Work Section

    @ViewBuilder
    func studentWorkSection(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Student header with context indicators
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StudentFormatter.displayName(for: student))
                        .font(AppTheme.ScaledFont.bodyBold)

                    // Quick context from presentation
                    if let entry = presentationViewModel.entries[student.id] {
                        HStack(spacing: 8) {
                            MiniUnderstandingIndicator(level: entry.understandingLevel)

                            if !entry.observation.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    addWorkDraft(for: student.id)
                } label: {
                    Label("Add Work", systemImage: SFSymbol.Action.plusCircleFill)
                        .font(AppTheme.ScaledFont.captionSemibold)
                }
                .buttonStyle(.bordered)
            }

            // Existing work items from database
            let existingWork = existingWorkItems(for: student.id)
            ForEach(existingWork) { work in
                existingWorkCard(work: work)
            }

            // Work drafts (new items being created in this session)
            let drafts = workDrafts[student.id] ?? []
            if drafts.isEmpty && existingWork.isEmpty {
                Text("No work items yet - add one or use bulk assignment")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(drafts) { draft in
                    workDraftCard(draft: draft, studentID: student.id)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    func workDraftCard(draft: WorkItemDraft, studentID: UUID) -> some View {
        WorkflowCard {
            VStack(alignment: .leading, spacing: 14) {
                // Title field
                WorkflowTextField(
                    label: "Title",
                    text: Binding(
                        get: { draft.title },
                        set: { newValue in
                            updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                $0.title = newValue
                            }
                        }
                    ),
                    placeholder: "Work Title"
                )

                // Work kind pills
                LabeledFieldSection(label: "Type") {
                    HStack(spacing: 8) {
                        PillButtonGroup(
                            items: WorkKind.allCases,
                            selection: draft.kind,
                            color: { $0.color },
                            icon: { $0.iconName },
                            label: { $0.shortLabel },
                            isSelected: { $0 == draft.kind },
                            onSelect: { kind in
                                updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.kind = kind }
                            }
                        )
                    }
                }

                // Status pills
                LabeledFieldSection(label: "Status") {
                    HStack(spacing: 8) {
                        PillButtonGroup(
                            items: WorkStatus.allCases,
                            selection: draft.status,
                            color: { $0.color },
                            icon: { $0.iconName },
                            label: { $0.displayName },
                            isSelected: { $0 == draft.status },
                            onSelect: { status in
                                updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.status = status }
                            }
                        )
                        Spacer()
                    }
                }

                // Dates
                WorkDatesRow(
                    checkInDate: Binding(
                        get: { draft.checkInDate },
                        set: { newValue in
                            updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                $0.checkInDate = newValue
                            }
                        }
                    ),
                    dueDate: Binding(
                        get: { draft.dueDate },
                        set: { newValue in
                            updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                $0.dueDate = newValue
                            }
                        }
                    ),
                    defaultCheckInDate: presentationViewModel.defaultCheckInDate,
                    defaultDueDate: presentationViewModel.defaultDueDate
                )

                // Notes field
                WorkflowTextField(
                    label: "Notes",
                    text: Binding(
                        get: { draft.notes },
                        set: { newValue in
                            updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                $0.notes = newValue
                            }
                        }
                    ),
                    placeholder: "Add notes...",
                    axis: .vertical,
                    lineLimit: 2...
                )

                // Completion details (if complete)
                if draft.status == .complete {
                    workDraftCompletionSection(draft: draft, studentID: studentID)
                }

                // Bottom actions
                HStack {
                    WorkflowInfoHint(text: "Full editor available after saving")
                    Spacer()
                    WorkflowDeleteButton {
                        removeWorkDraft(studentID: studentID, draftID: draft.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func workDraftCompletionSection(draft: WorkItemDraft, studentID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExpandableSectionButton(
                title: "Completion Details",
                isExpanded: draft.showMoreDetails,
                action: {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        updateWorkDraft(studentID: studentID, draftID: draft.id) {
                            $0.showMoreDetails.toggle()
                        }
                    }
                }
            )

            if draft.showMoreDetails {
                VStack(alignment: .leading, spacing: 12) {
                    // Outcome picker
                    LabeledFieldSection(label: "Outcome") {
                        FlowLayout(spacing: 8) {
                            PillButtonGroup(
                                items: CompletionOutcome.allCases,
                                selection: draft.completionOutcome,
                                color: { $0.color },
                                icon: { $0.iconName },
                                label: { $0.displayName },
                                isSelected: { $0 == draft.completionOutcome },
                                onSelect: { outcome in
                                    updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                        $0.completionOutcome = outcome
                                    }
                                }
                            )
                        }
                    }

                    // Completion note
                    WorkflowTextField(
                        label: "Completion Note",
                        text: Binding(
                            get: { draft.completionNote },
                            set: { newValue in
                                updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                    $0.completionNote = newValue
                                }
                            }
                        ),
                        placeholder: "Add completion note...",
                        axis: .vertical,
                        lineLimit: 2...
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .cardBackground(color: Color.green.opacity(0.08), cornerRadius: 10)
    }

    // MARK: - Existing Work Card

    @ViewBuilder
    func existingWorkCard(work: WorkModel) -> some View {
        WorkflowCard(
            backgroundColor: Color.blue.opacity(0.06),
            borderColor: Color.blue.opacity(0.2)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title.isEmpty ? lessonName : work.title)
                            .font(AppTheme.ScaledFont.bodySemibold)

                        Text("Created \(work.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    WorkflowBadge(
                        icon: work.status.iconName,
                        text: work.status.displayName,
                        color: work.status.color
                    )
                }

                // Work kind badge
                if let kind = work.kind {
                    WorkflowBadge(
                        icon: kind.iconName,
                        text: kind.shortLabel,
                        color: kind.color
                    )
                }

                // Due date if set
                if let dueAt = work.dueAt {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 10))
                        Text("Due: \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppTheme.ScaledFont.captionSmall)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Work Draft Management

    func addWorkDraft(for studentID: UUID) {
        let assignment = presentationViewModel.entries[studentID]?.assignment ?? ""
        let draft = createWorkDraft(for: studentID, title: assignment)
        workDrafts[studentID, default: []].append(draft)
    }

    func createWorkDraft(
        for studentID: UUID, title: String = "",
        kind: WorkKind = .followUpAssignment,
        applyDefaultDates: Bool = false
    ) -> WorkItemDraft {
        var draft = WorkItemDraft(
            studentID: studentID,
            title: title.isEmpty ? "" : title,
            kind: kind, checkInStyle: bulkCheckInStyle
        )

        if applyDefaultDates {
            if presentationViewModel.defaultCheckInEnabled {
                draft.checkInDate = presentationViewModel.defaultCheckInDate
            }
            if presentationViewModel.defaultDueEnabled {
                draft.dueDate = presentationViewModel.defaultDueDate
            }
        }

        return draft
    }

    func removeWorkDraft(studentID: UUID, draftID: UUID) {
        workDrafts[studentID]?.removeAll { $0.id == draftID }
    }

    func updateWorkDraft(studentID: UUID, draftID: UUID, update: (inout WorkItemDraft) -> Void) {
        guard let index = workDrafts[studentID]?.firstIndex(where: { $0.id == draftID }) else { return }
        update(&workDrafts[studentID]![index])
    }

    func syncAssignmentToWorkDraft(studentID: UUID, assignment: String) {
        let trimmedAssignment = assignment.trimmed()

        if workDrafts[studentID]?.isEmpty ?? true {
            if !trimmedAssignment.isEmpty {
                let draft = createWorkDraft(for: studentID, title: trimmedAssignment)
                workDrafts[studentID, default: []].append(draft)
            }
        } else if let firstIndex = workDrafts[studentID]?.indices.first {
            workDrafts[studentID]?[firstIndex].title = trimmedAssignment
        }
    }
}
