import SwiftUI
import CoreData

/// Displays a list of prerequisite or related lessons by resolving their UUIDs to names.
struct LessonRelationshipsSection: View {
    let title: String
    let icon: String
    let lessonIDs: [UUID]
    let viewContext: NSManagedObjectContext

    @Environment(\.dependencies) private var dependencies

    var body: some View {
        // Resolved once per pass, from the workspace's live lesson catalog.
        let lessons = resolvedLessons
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            HStack(spacing: AppTheme.Spacing.small + 2) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            ForEach(lessons) { lesson in
                HStack(spacing: AppTheme.Spacing.small) {
                    Text("•").font(AppTheme.ScaledFont.body)
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(AppTheme.ScaledFont.body)
                    if !lesson.area.isEmpty {
                        Text("(\(lesson.area))")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if lessons.isEmpty {
                Text("Lessons not found")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, AppTheme.Spacing.verySmall)
    }

    private var resolvedLessons: [CDLesson] {
        let catalog = dependencies.lessonCatalog
        return lessonIDs.compactMap { catalog.lesson(id: $0, in: viewContext) }
    }
}
