// NoteEditorStudentSelection.swift
// Student selection UI for UnifiedNoteEditor - extracted from NoteEditorSections.swift

import SwiftUI
import SwiftData

// MARK: - Student Selection Extension

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(Array(detectedStudentIDs), id: \.self) { studentID in
                        if let student = students.first(where: { $0.id == studentID }) {
                            let isSelected = selectedStudentIDs.contains(studentID)
                            let studentName = displayName(for: student)
                            Button {
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
                            .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxsmall)
            }
        }
        .frame(minHeight: 44)
        .opacity(detectedStudentIDs.isEmpty ? 0 : 1)
        .adaptiveAnimation(.easeInOut(duration: UIConstants.AnimationDuration.quick), value: detectedStudentIDs)
        .accessibilityHidden(detectedStudentIDs.isEmpty)
    }

    // MARK: - Student Selection Section

    var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Selected Students")
                .font(AppTheme.ScaledFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.small) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(Array(selectedStudentIDs), id: \.self) { studentID in
                            if let student = students.first(where: { $0.id == studentID }) {
                                let studentName = displayName(for: student)
                                HStack(spacing: AppTheme.Spacing.xsmall) {
                                    Text(studentName)
                                        .font(AppTheme.ScaledFont.caption.weight(.medium))
                                    Button {
                                        selectedStudentIDs.remove(studentID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.scaledRounded(.caption2, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Remove \(studentName)")
                                }
                                .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
                                .padding(.vertical, AppTheme.Spacing.verySmall)
                                .foregroundStyle(.primary)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                                )
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(studentName), selected")
                                .accessibilityHint("Contains remove button")
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xxsmall)
                }

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
                .accessibilityHint("Double tap to open student picker")
                .popover(isPresented: $showingStudentPicker, arrowEdge: .top) {
                    studentPickerPopover
                }
            }
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
