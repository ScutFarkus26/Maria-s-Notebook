import SwiftUI

/// Read-only display of a single CDSampleWorkEntity within a lesson detail view.
struct SampleWorkRow: View {
    let sampleWork: CDSampleWorkEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(sampleWork.orderIndex + 1).")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)

                Text(sampleWork.title.isEmpty ? "Untitled Work" : sampleWork.title)
                    .font(AppTheme.ScaledFont.bodySemibold)

                Spacer()

                if let kind = sampleWork.workKind {
                    HStack(spacing: 4) {
                        Image(systemName: kind.iconName)
                            .font(.caption2)
                        Text(kind.shortLabel)
                            .font(AppTheme.ScaledFont.captionSemibold)
                    }
                    .foregroundStyle(kind.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(kind.color.opacity(UIConstants.OpacityConstants.accent)))
                }
            }

            // Show step count
            let stepCount = sampleWork.stepCount
            if stepCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)
                    Text("\(stepCount) step\(stepCount == 1 ? "" : "s")")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !sampleWork.notes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)
                    Text(sampleWork.notes)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
    }
}
