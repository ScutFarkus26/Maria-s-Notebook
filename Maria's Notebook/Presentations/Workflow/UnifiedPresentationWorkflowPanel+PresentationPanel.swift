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
        let hasNotes = !(entry?.observation.trimmed() ?? "").isEmpty
        let pillColor: Color = hasNotes ? Color.accentColor : Color.secondary

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
                WorkflowSectionHeader(title: "Student Observations", icon: "person.2.fill")

                Spacer()

                let completed = presentationViewModel.entries.values.filter {
                    !$0.observation.trimmed().isEmpty
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
        let hasContent = !(entry?.observation.trimmed().isEmpty ?? true)

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
                    isExpanded: isExpanded
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

}
