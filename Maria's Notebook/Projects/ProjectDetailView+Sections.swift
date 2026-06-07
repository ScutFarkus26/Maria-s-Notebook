import SwiftUI
import CoreData

extension ProjectDetailView {
    var lessonConnectionsSection: some View {
        SectionCard(title: "Lesson Connections", systemImage: SFSymbol.Education.bookClosed) {
            if linkedLessons.isEmpty {
                Text("No lessons linked yet")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: AppTheme.Spacing.small)],
                    spacing: AppTheme.Spacing.small
                ) {
                    ForEach(linkedLessons, id: \.objectID) { lesson in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                            Text(lesson.name)
                                .font(AppTheme.ScaledFont.bodySemibold)
                                .lineLimit(2)
                            Text([lesson.area, lesson.sequence].filter { !$0.isEmpty }.joined(separator: " / "))
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.small)
                        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                        .cornerRadius(UIConstants.CornerRadius.small)
                    }
                }
            }
        }
    }

    var questionsSection: some View {
        SectionCard(title: "Questions & Next Steps", systemImage: "questionmark.bubble") {
            if openQuestions.isEmpty {
                Text("Add student questions and next steps during a check-in")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    ForEach(openQuestions.prefix(8)) { question in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                Text(question.text)
                                    .font(AppTheme.ScaledFont.body)
                                Text(DateFormatters.mediumDate.string(from: question.session.meetingDate ?? Date()))
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, AppTheme.Spacing.xxsmall)

            content
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large + 2, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
}
