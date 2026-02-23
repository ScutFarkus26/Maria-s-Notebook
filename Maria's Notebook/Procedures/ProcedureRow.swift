import SwiftUI
import SwiftData

/// A row displaying a procedure item
struct ProcedureRow: View {
    let procedure: Procedure

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: procedure.displayIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(.accent)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(procedure.title)
                    .font(.headline)
                    .lineLimit(1)

                if !procedure.summary.isEmpty {
                    Text(procedure.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("Updated \(procedure.modifiedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
    }
}

/// A compact row for procedure lists without card styling
struct ProcedureCompactRow: View {
    let procedure: Procedure

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: procedure.displayIcon)
                .foregroundStyle(.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(procedure.title)
                    .lineLimit(1)

                if !procedure.summary.isEmpty {
                    Text(procedure.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ProcedureRow(
            procedure: Procedure(
                title: "Morning Arrival",
                summary: "Steps for welcoming students and starting the day",
                content: "## Overview\nThis procedure outlines...",
                category: .dailyRoutines,
                icon: "sunrise"
            )
        )

        ProcedureRow(
            procedure: Procedure(
                title: "Fire Drill",
                summary: "Emergency evacuation procedure",
                content: "## Steps\n1. Alert students...",
                category: .safety
            )
        )

        ProcedureRow(
            procedure: Procedure(
                title: "Friday Schedule",
                summary: "Modified schedule for end-of-week activities",
                content: "## Friday Routine\n...",
                category: .specialSchedules
            )
        )
    }
    .padding()
}
