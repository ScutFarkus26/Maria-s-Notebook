import SwiftUI

struct NextLessonRow: View {
    let snapshot: StudentLessonSnapshot
    let lesson: Lesson?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson?.name ?? "Lesson")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
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
    let snapshots: [StudentLessonSnapshot]
    let lessonsByID: [UUID: Lesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Lessons")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(snapshots.count)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
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
