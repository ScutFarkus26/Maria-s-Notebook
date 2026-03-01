import SwiftUI

struct NextLessonRow: View {
    let snapshot: LessonAssignmentSnapshot
    let lesson: Lesson?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson?.name ?? "Lesson")
                    .font(AppTheme.ScaledFont.titleSmall)
                if let subject = lesson?.subject, !subject.isEmpty {
                    Text(subject)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct NextLessonsSection: View {
    let snapshots: [LessonAssignmentSnapshot]
    let lessonsByID: [UUID: Lesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Lessons")
                    .font(AppTheme.ScaledFont.header)
                Spacer()
                Text("\(snapshots.count)")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if snapshots.isEmpty {
                Text("No lessons scheduled yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshots, id: \.id) { sl in
                        NextLessonRow(snapshot: sl, lesson: lessonsByID[sl.lessonID])
                    }
                }
            }
        }
    }
}

#Preview {
    Text("NextLessonsSection requires real data")
}
