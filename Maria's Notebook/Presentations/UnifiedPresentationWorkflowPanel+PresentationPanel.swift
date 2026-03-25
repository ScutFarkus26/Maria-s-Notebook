import SwiftUI
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
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Status Section
                    presentationStatusSection

                    Divider()
                        .padding(.horizontal, 16)

                    // Group Observation Section
                    groupObservationSection

                    Divider()
                        .padding(.horizontal, 16)

                    // Student Entries Section
                    studentEntriesSection
                }
                .padding(.vertical, 16)
            }
            .dismissKeyboardOnScroll()
        }
        .overlay(alignment: .bottomTrailing) {
            studentNavigatorButton
                .padding(16)
        }
    }

    // MARK: - Student Navigator Button

    var studentNavigatorButton: some View {
        Menu {
            ForEach(sortedStudents) { student in
                Button {
                    scrollToStudent(student.id)
                } label: {
                    HStack {
                        Text(StudentFormatter.displayName(for: student))
                        Spacer()
                        if let level = presentationViewModel.entries[student.id]?.understandingLevel {
                            Text("\(level)")
                                .foregroundStyle(UnderstandingLevel.color(for: level))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
        }
    }

    func scrollToStudent(_ studentID: UUID) {
        // Toggle expansion to ensure student is visible
        if !presentationViewModel.expandedStudentIDs.contains(studentID) {
            presentationViewModel.expandedStudentIDs.insert(studentID)
        }
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

    // MARK: - Student Entries Section

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
            }
        }
        .padding(.horizontal, 16)
    }

    func studentEntryRow(for student: Student) -> some View {
        let isExpanded = presentationViewModel.expandedStudentIDs.contains(student.id)
        let entry = presentationViewModel.entries[student.id]
        let hasContent = !(entry?.observation.isEmpty ?? true) || !(entry?.assignment.isEmpty ?? true)
        let level = entry?.understandingLevel ?? 3

        return VStack(spacing: 0) {
            // Header row
            Button {
                _ = adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        presentationViewModel.expandedStudentIDs.remove(student.id)
                    } else {
                        presentationViewModel.expandedStudentIDs.insert(student.id)
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
    func studentExpandedContent(for student: Student) -> some View {
        VStack(spacing: 12) {
            // Understanding level picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Understanding")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                UnderstandingLevelRow(selectedLevel: Binding(
                    get: { presentationViewModel.entries[student.id]?.understandingLevel ?? 3 },
                    set: { presentationViewModel.entries[student.id]?.understandingLevel = $0 }
                ))
            }

            // Observation
            VStack(alignment: .leading, spacing: 6) {
                Text("Observation")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField("Note about this student...", text: Binding(
                    get: { presentationViewModel.entries[student.id]?.observation ?? "" },
                    set: { presentationViewModel.entries[student.id]?.observation = $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .padding(.top, -4)
    }

    // MARK: - Helpers

    func applyUnderstandingToAll(level: Int) {
        var count = 0
        for student in students where presentationViewModel.entries[student.id] != nil {
            presentationViewModel.entries[student.id]?.understandingLevel = level
            count += 1
        }

        // Show toast notification
        _ = adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
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
            _ = adaptiveWithAnimation(.easeInOut(duration: 0.3)) {
                showBulkAppliedToast = false
            }
        }
    }
}
