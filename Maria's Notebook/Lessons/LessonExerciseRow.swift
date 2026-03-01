import SwiftUI

/// Read-only display of a single LessonExercise within a detail view.
struct LessonExerciseRow: View {
    let exercise: LessonExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(exercise.orderIndex + 1).")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Text(exercise.title.isEmpty ? "Untitled Exercise" : exercise.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Spacer()
            }

            if !exercise.preparation.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "hammer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)
                    Text(exercise.preparation)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !exercise.presentationStepItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(exercise.presentationStepItems.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1).")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)
                            Text(step)
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !exercise.notes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)
                    Text(exercise.notes)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
    }
}
