import SwiftUI
import CoreData

/// A row displaying a procedure item
struct ProcedureRow: View {
    let procedure: Procedure

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
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

                Text("Updated \(procedure.modifiedAt ?? Date(), style: .relative) ago")
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
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let p1 = Procedure(context: ctx)
    p1.title = "Morning Arrival"
    p1.summary = "Steps for welcoming students and starting the day"
    p1.content = "## Overview\nThis procedure outlines..."
    p1.category = .dailyRoutines
    p1.icon = "sunrise"

    let p2 = Procedure(context: ctx)
    p2.title = "Fire Drill"
    p2.summary = "Emergency evacuation procedure"
    p2.content = "## Steps\n1. Alert students..."
    p2.category = .safety

    let p3 = Procedure(context: ctx)
    p3.title = "Friday Schedule"
    p3.summary = "Modified schedule for end-of-week activities"
    p3.content = "## Friday Routine\n..."
    p3.category = .specialSchedules

    return VStack(spacing: 12) {
        ProcedureRow(procedure: p1)
        ProcedureRow(procedure: p2)
        ProcedureRow(procedure: p3)
    }
    .padding()
    .previewEnvironment(using: stack)
}
