// SequenceRecapSection.swift
// Top-level collapsible section that shows the sequence recap on the
// presentation detail view. Renders one nested DisclosureGroup per student
// with a progress chip; per-student lesson rows are in SequenceRecapBlocks.swift.

import SwiftUI

// MARK: - Top-Level Section

struct SequenceRecapSection: View {
    let recap: SequenceRecap
    let onUpdateState: (UUID, UUID, LessonPresentationState) -> Void
    let onOpenWork: (UUID) -> Void
    let onCycleWorkStatus: (UUID, WorkStatus) -> Void
    let onAddWork: (UUID, UUID, UUID?) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(recap.studentEntries) { student in
                    SequenceRecapStudentSection(
                        student: student,
                        areaColor: AppColors.color(forArea: recap.area),
                        onUpdateState: onUpdateState,
                        onOpenWork: onOpenWork,
                        onCycleWorkStatus: onCycleWorkStatus,
                        onAddWork: onAddWork
                    )
                }
                if recap.studentEntries.isEmpty {
                    Text("No students in this presentation yet.")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        } label: {
            collapsedHeader
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var collapsedHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.title3)
                .foregroundStyle(AppColors.color(forArea: recap.area))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Group: \(recap.sequenceName)")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                Text(summaryLine)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var summaryLine: String {
        let lessonCount = recap.lessonsInSequence.count
        let studentCount = recap.studentEntries.count
        let lessonWord = lessonCount == 1 ? "lesson" : "lessons"
        let studentWord = studentCount == 1 ? "student" : "students"
        return "\(lessonCount) \(lessonWord) · \(studentCount) \(studentWord)"
    }
}

// MARK: - Per-Student Section

struct SequenceRecapStudentSection: View {
    let student: SequenceRecapStudentEntry
    let areaColor: Color
    let onUpdateState: (UUID, UUID, LessonPresentationState) -> Void
    let onOpenWork: (UUID) -> Void
    let onCycleWorkStatus: (UUID, WorkStatus) -> Void
    let onAddWork: (UUID, UUID, UUID?) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(student.lessonEntries) { entry in
                    SequenceRecapLessonRow(
                        entry: entry,
                        areaColor: areaColor,
                        studentID: student.id,
                        onUpdateState: onUpdateState,
                        onOpenWork: onOpenWork,
                        onCycleWorkStatus: onCycleWorkStatus,
                        onAddWork: onAddWork
                    )
                }
                if !student.orphanNotes.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Other notes")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    ForEach(student.orphanNotes) { note in
                        SequenceRecapNoteBlock(note: note)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            studentHeader
        }
    }

    private var studentHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(student.studentName)
                .font(AppTheme.ScaledFont.bodySemibold)
            Spacer(minLength: 0)
            progressChip
        }
    }

    private var progressChip: some View {
        let proficientCount = student.lessonEntries.filter { $0.outcomeState == .proficient }.count
        let totalCount = student.lessonEntries.count
        let color = ProgressChipColor.color(proficient: proficientCount, total: totalCount)
        return Text("\(proficientCount) / \(totalCount) mastered")
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

// MARK: - Progress Chip Color

enum ProgressChipColor {
    static func color(proficient: Int, total: Int) -> Color {
        guard total > 0 else { return .secondary }
        let ratio = Double(proficient) / Double(total)
        if ratio >= 0.75 { return .green }
        if ratio >= 0.4 { return .blue }
        if ratio > 0 { return .orange }
        return .secondary
    }
}
