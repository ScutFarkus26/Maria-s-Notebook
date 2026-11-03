// PresentationHowItWentView+Summary.swift
// The How It Went sheet's last card: what Done will write, in plain words.

import SwiftUI

extension PresentationHowItWentView {
    var summaryLines: [String] {
        let noteCount = (session.groupNote.trimmed().isEmpty ? 0 : 1)
            + studentIDs.filter { !(session.childNotes[$0]?.trimmed().isEmpty ?? true) }.count
        return PresentationSessionSummary.lines(.init(
            children: students.compactMap { student in
                student.id.map { PresentationSessionSummary.Child(id: $0, name: student.shortName) }
            },
            pending: session.pendingDecisions(for: studentIDs),
            decisions: session.decisions(for: studentIDs),
            checkIn: session.checkIn,
            checkInChanged: session.checkInChanged,
            noteCount: noteCount,
            lessonName: lesson.name,
            nextLessonName: nextLessonName,
            followUpDetail: session.followUpDetail,
            alsoReady: session.newlyAlsoReady(for: studentIDs),
            noLongerReady: session.noLongerReady(for: studentIDs)
        ))
    }

    var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When you press Done")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            let lines = summaryLines
            if lines.isEmpty {
                Text("Nothing new to save. Done just closes.")
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Color.accentColor)
                        Text(line).font(AppTheme.ScaledFont.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color.primary.opacity(UIConstants.OpacityConstants.whisper),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
        )
    }
}
