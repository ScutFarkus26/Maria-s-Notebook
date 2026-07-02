// NoteEditorStudentSelection.swift
// CDStudent selection UI for UnifiedNoteEditor - extracted from NoteEditorSections.swift

import SwiftUI
import CoreData

// MARK: - CDStudent Selection Extension

extension UnifiedNoteEditor {

    // MARK: - Surfacing Banner (Detected Names)

    @ViewBuilder
    var surfacingBanner: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Detected Names")
                    .font(AppTheme.ScaledFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            detectedStudentsScroll
        }
        .frame(minHeight: 44)
        .opacity(detectedStudentIDs.isEmpty ? 0 : 1)
        .adaptiveAnimation(.easeInOut(duration: UIConstants.AnimationDuration.quick), value: detectedStudentIDs)
        .accessibilityHidden(detectedStudentIDs.isEmpty)
    }

    private var detectedStudentsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(Array(detectedStudentIDs), id: \.self) { studentID in
                    if let student: CDStudent = students.first(where: { $0.id == studentID }) {
                        detectedStudentButton(studentID: studentID, student: student)
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xxsmall)
        }
    }

    private func detectedStudentButton(studentID: UUID, student: CDStudent) -> some View {
        let isSelected: Bool = selectedStudentIDs.contains(studentID)
        let studentName: String = displayName(for: student)
        return Button {
            if isSelected {
                selectedStudentIDs.remove(studentID)
            } else {
                selectedStudentIDs.insert(studentID)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xsmall) {
                Text(studentName)
                    .font(AppTheme.ScaledFont.caption.weight(.medium))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.scaledRounded(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                            : Color.secondary.opacity(UIConstants.OpacityConstants.light)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(studentName)
        .accessibilityHint(isSelected ? "Deselects this student" : "Selects this student")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - CDStudent Selection Section

    var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Selected Students")
                .font(AppTheme.ScaledFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.small) {
                selectedStudentsScroll
                addStudentButton
            }
        }
    }

    private var selectedStudentsScroll: some View {
        SelectedStudentChipsRow(
            students: Array(selectedStudentIDs).compactMap { id in students.first { $0.id == id } },
            label: { displayName(for: $0) },
            onRemove: { student in
                if let id = student.id { selectedStudentIDs.remove(id) }
            }
        )
    }

    private var addStudentButton: some View {
        Button {
            showingStudentPicker = true
        } label: {
            HStack(spacing: AppTheme.Spacing.xsmall) {
                Image(systemName: "plus.circle.fill")
                    .font(.scaledRounded(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Add")
                    .font(AppTheme.ScaledFont.caption.weight(.medium))
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .foregroundStyle(Color.accentColor)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add student")
        .accessibilityHint("Opens the student picker")
        .popover(isPresented: $showingStudentPicker, arrowEdge: .top) {
            studentPickerPopover
        }
    }

    var studentPickerPopover: some View {
        StudentPickerPopover(
            students: students,
            selectedIDs: $selectedStudentIDs,
            onDone: {
                showingStudentPicker = false
            }
        )
        .padding(AppTheme.Spacing.compact)
        .frame(minWidth: 320)
    }
}
