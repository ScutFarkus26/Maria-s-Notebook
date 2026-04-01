// GoingOutSidebarRow.swift
// Row for the going-out list showing title, students, status, and date.

import SwiftUI

struct GoingOutSidebarRow: View {
    let goingOut: CDGoingOut

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: goingOut.status.icon)
                .font(.title3)
                .foregroundStyle(goingOut.status.color)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(goingOut.title.isEmpty ? "Untitled Going-Out" : goingOut.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !goingOut.destination.isEmpty {
                        Text(goingOut.destination)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !goingOut.studentIDsArray.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text("\(goingOut.studentIDsArray.count) students")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                GoingOutStatusBadge(status: goingOut.status)

                if let date = goingOut.proposedDate {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
        .shadow(color: CardStyle.shadowColor, radius: CardStyle.shadowRadius, y: 1)
    }
}
