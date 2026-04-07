import SwiftUI
import CoreData
import os

// MARK: - Presentation Panel

extension UnifiedPresentationWorkflowPanel {

    // MARK: - Presentation Panel

    var presentationPanel: some View {
        VStack(spacing: 0) {
            WorkflowPanelHeader(title: "Presentation Notes")

            Divider()

            // Progress Indicator
            WorkflowProgressIndicator(
                totalStudents: students.count,
                studentsWithUnderstanding: studentsWithUnderstanding,
                studentsWithNotes: studentsWithNotes,
                hasGroupObservation: hasGroupObservation
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))

            Divider()

            // Student navigation pill bar
            studentPillBar
                .padding(.vertical, 8)
                .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Progression rules banner
                        if let rules = presentationViewModel.resolvedRules,
                           rules.requiresPractice || rules.requiresTeacherConfirmation {
                            progressionRulesBanner(rules)
                        }

                        // Status Section
                        presentationStatusSection

                        Divider()
                            .padding(.horizontal, 16)

                        // Group Observation Section
                        groupObservationSection

                        Divider()
                            .padding(.horizontal, 16)

                        // CDStudent Entries Section
                        studentEntriesSection
                    }
                    .padding(.vertical, 16)
                }
                .dismissKeyboardOnScroll()
                .onChange(of: scrollTargetStudentID) { _, newValue in
                    if let id = newValue {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .top)
                        }
                        scrollTargetStudentID = nil
                    }
                }
            }
        }
    }

    // MARK: - Student Pill Bar

    var studentPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sortedStudents) { student in
                    studentPill(student)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    func studentPill(_ student: CDStudent) -> some View {
        let id = student.id ?? UUID()
        let entry = presentationViewModel.entries[id]
        let hasNotes = !(entry?.observation ?? "").isEmpty
        let hasLevel = entry?.understandingLevel != nil && entry?.understandingLevel != 3

        let pillColor: Color = if hasNotes && hasLevel {
            AppColors.success
        } else if hasNotes || hasLevel {
            Color.accentColor
        } else {
            Color.secondary
        }

        return Button {
            if !presentationViewModel.expandedStudentIDs.contains(id) {
                presentationViewModel.expandedStudentIDs.insert(id)
            }
            scrollTargetStudentID = id
        } label: {
            Text(student.firstName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(pillColor == Color.secondary ? Color.secondary : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(pillColor == Color.secondary
                              ? Color.secondary.opacity(UIConstants.OpacityConstants.light)
                              : pillColor)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presentation Status Section

    var presentationStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkflowSectionHeader(title: "Presentation Status", icon: "flag.fill")

            HStack(spacing: 12) {
                ForEach(UnifiedPostPresentationSheet.PresentationStatus.allCases) { status in
                    WorkflowStatusButton(
                        icon: status.systemImage,
                        title: status.title,
                        color: status.tint,
                        isSelected: presentationViewModel.status == status,
                        action: { presentationViewModel.status = status }
                    )
                }
            }

            Divider()

            // Apply Understanding to All
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Apply Understanding to All")

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            applyUnderstandingToAll(level: level)
                        } label: {
                            UnderstandingLevelIndicator(level: level, size: 28)
                        }
                        .buttonStyle(.plain)
                        .help(UnderstandingLevel.label(for: level))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Group Observation Section

    var groupObservationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkflowSectionHeader(title: "Group Observation", icon: "text.bubble.fill")

            TextField(
                "Notes about the presentation overall...",
                text: $presentationViewModel.groupObservation, axis: .vertical
            )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - CDStudent Entries Section

    var studentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WorkflowSectionHeader(title: "Student Status & Notes", icon: "person.2.fill")

                Spacer()

                let completed = presentationViewModel.entries.values.filter {
                    !$0.observation.isEmpty || !$0.assignment.isEmpty
                }.count
                Text("\(completed)/\(presentationViewModel.entries.count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.tertiary)
            }

            ForEach(sortedStudents, id: \.id) { student in
                studentEntryRow(for: student)
                    .id(student.id)
            }
        }
        .padding(.horizontal, 16)
    }

    func studentEntryRow(for student: CDStudent) -> some View {
        let studentID = student.id ?? UUID()
        let isExpanded = presentationViewModel.expandedStudentIDs.contains(studentID)
        let entry = presentationViewModel.entries[studentID]
        let hasContent = !(entry?.observation.isEmpty ?? true) || !(entry?.assignment.isEmpty ?? true)
        let level = entry?.understandingLevel ?? 3

        return VStack(spacing: 0) {
            // Header row
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        presentationViewModel.expandedStudentIDs.remove(studentID)
                    } else {
                        presentationViewModel.expandedStudentIDs.insert(studentID)
                    }
                }
            } label: {
                StudentEntryRowHeader(
                    studentName: StudentFormatter.displayName(for: student),
                    hasContent: hasContent,
                    isExpanded: isExpanded,
                    understandingLevel: level
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                studentExpandedContent(for: student)
            }
        }
    }

    @ViewBuilder
    func studentExpandedContent(for student: CDStudent) -> some View {
        let studentID = student.id ?? UUID()
        VStack(spacing: 12) {
            // Understanding level picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Understanding")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                UnderstandingLevelRow(selectedLevel: Binding(
                    get: { presentationViewModel.entries[studentID]?.understandingLevel ?? 3 },
                    set: { presentationViewModel.entries[studentID]?.understandingLevel = $0 }
                ))
            }

            // Proficiency confirmation (when required by progression rules)
            if presentationViewModel.requiresConfirmation {
                HStack {
                    Label("Ready for next lesson", systemImage: "checkmark.seal")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { presentationViewModel.confirmedStudentIDs.contains(studentID) },
                        set: { _ in presentationViewModel.toggleConfirmation(for: studentID) }
                    ))
                    .labelsHidden()
                }
            }

            // Observation
            VStack(alignment: .leading, spacing: 6) {
                Text("Observation")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField("Note about this student...", text: Binding(
                    get: { presentationViewModel.entries[studentID]?.observation ?? "" },
                    set: { presentationViewModel.entries[studentID]?.observation = $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
        .padding(.top, -4)
    }

    // MARK: - Progression Rules Banner

    @ViewBuilder
    func progressionRulesBanner(_ rules: LessonProgressionRules.ResolvedRules) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Progression Rules", systemImage: "arrow.right.circle.fill")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.orange)

            if rules.requiresPractice {
                Label("Follow-up practice required", systemImage: "pencil.and.list.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if rules.requiresTeacherConfirmation {
                Label("Teacher confirmation required before next lesson", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(UIConstants.OpacityConstants.accent))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    func applyUnderstandingToAll(level: Int) {
        var count = 0
        for student in students {
            guard let id = student.id, presentationViewModel.entries[id] != nil else { continue }
            presentationViewModel.entries[id]?.understandingLevel = level
            count += 1
        }

        // Show toast notification
        adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
            bulkAppliedMessage = "Applied \(UnderstandingLevel.label(for: level))"
                + " to \(count) student\(count == 1 ? "" : "s")"
            showBulkAppliedToast = true
        }

        // Auto-hide after 2 seconds
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                Self.logger.debug("Toast auto-hide interrupted: \(error)")
            }
            adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }
}
