//
//  PracticeSessionCompactRow.swift
//  Maria's Notebook
//
//  Compact row for displaying practice sessions
//

import SwiftUI

struct PracticeSessionCompactRow: View {
    let session: PracticeSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isGroupSession ? "person.2" : "person")
                .font(.system(size: 12))
                .foregroundStyle(.purple)

            Text(session.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)

            if let duration = session.durationFormatted {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(duration)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(session.participantCount) \(session.participantCount == 1 ? "student" : "students")")
                .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.08))
        )
    }
}
