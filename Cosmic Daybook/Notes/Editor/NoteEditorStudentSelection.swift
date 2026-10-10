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
        let studentName: String = student.shortName
        return Button {
            if isSelected {
                chooseStudents(selectedStudentIDs.subtracting([studentID]))
            } else {
                chooseStudents(selectedStudentIDs.union([studentID]))
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
            .capsuleFill(
                isSelected
                    ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent)
                    : Color.secondary.opacity(UIConstants.OpacityConstants.light)
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

    /// Chips for every chosen child, a withdrawn one included: looked up among
    /// enrolled children only, a child who had left got no chip and couldn't
    /// be taken off the note. A child no longer in the notebook at all gets a
    /// "Student removed" chip.
    private var selectedStudentsScroll: some View {
        let roster = dependencies.roster
        let known = selectedStudentIDs.compactMap { roster.student(id: $0) }
            .sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
        let unknown = selectedStudentIDs.filter { roster.student(id: $0) == nil }
            .sorted { $0.uuidString < $1.uuidString }
        return HStack(spacing: AppTheme.Spacing.small) {
            SelectedStudentChipsRow(
                students: known,
                label: { $0.shortName },
                onRemove: { student in
                    if let id = student.id { chooseStudents(selectedStudentIDs.subtracting([id])) }
                }
            )
            ForEach(unknown, id: \.self) { id in
                Button {
                    chooseStudents(selectedStudentIDs.subtracting([id]))
                } label: {
                    Label("Student removed", systemImage: "xmark.circle.fill")
                        .font(AppTheme.ScaledFont.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove a student who is no longer in the notebook")
            }
        }
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
            .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
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
            selectedIDs: Binding(
                get: { selectedStudentIDs },
                set: { chooseStudents($0) }
            ),
            onDone: {
                showingStudentPicker = false
            }
        )
        .padding(AppTheme.Spacing.compact)
        .frame(minWidth: 320)
    }

    // MARK: - Choosing Children

    /// Sets the chosen children from something she did (a chip, a detected
    /// name, the picker, Suggest Tags), remembering whom she took off so the
    /// name finder leaves them off while she keeps typing.
    func chooseStudents(_ ids: Set<UUID>) {
        selectedStudentIDs = NoteEditorChildChoice.choose(
            ids, from: selectedStudentIDs, deselected: &deselectedStudentIDs
        )
    }
}

// MARK: - Child Choice

/// Who stays chosen in the note editor, apart from the view so it can be
/// tested. Until 2026-10-10 a child she deselected came back on the next
/// keystroke that mentioned her.
enum NoteEditorChildChoice {
    /// The chosen set after a change she made: records whom she took off and
    /// forgets that for anyone she put back.
    static func choose(_ new: Set<UUID>, from old: Set<UUID>, deselected: inout Set<UUID>) -> Set<UUID> {
        deselected.formUnion(old.subtracting(new))
        deselected.subtract(new)
        return new
    }

    /// The chosen set after the name finder ran (`before` → `after`): a child
    /// it added comes off again if she took her off, or if she is named in
    /// the opened note's own text. Others it added stay: typing "Sarah M"
    /// still chooses Sarah M after she took Sarah K off.
    static func afterNameFinder(
        before: Set<UUID>, after: Set<UUID>, deselected: Set<UUID>, openedTextNames: Set<UUID>
    ) -> Set<UUID> {
        after.subtracting(after.subtracting(before).intersection(deselected.union(openedTextNames)))
    }
}
