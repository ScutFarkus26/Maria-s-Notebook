import SwiftUI

struct NextLessonsListView: View {
    let isLoading: Bool
    let lessons: [LessonAssignmentSnapshot]
    let countText: String
    let lessonName: (LessonAssignmentSnapshot) -> String
    let lessonSubject: (LessonAssignmentSnapshot) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Lessons")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text(countText)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if isLoading {
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else if lessons.isEmpty {
                Text("No lessons scheduled yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(lessons, id: \.id) { sl in
                        HStack(spacing: 12) {
                            Image(systemName: "book")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lessonName(sl))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let subject = lessonSubject(sl), !subject.isEmpty {
                                    Text(subject)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
