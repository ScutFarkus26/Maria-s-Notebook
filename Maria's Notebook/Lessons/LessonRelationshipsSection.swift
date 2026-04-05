import SwiftUI
import CoreData

/// Displays a list of prerequisite or related lessons by resolving their UUIDs to names.
struct LessonRelationshipsSection: View {
    let title: String
    let icon: String
    let lessonIDs: [UUID]
    let viewContext: NSManagedObjectContext

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            HStack(spacing: AppTheme.Spacing.small + 2) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            ForEach(resolvedLessons) { lesson in
                HStack(spacing: AppTheme.Spacing.small) {
                    Text("•").font(AppTheme.ScaledFont.body)
                    Text(lesson.name.isEmpty ? "Untitled CDLesson" : lesson.name)
                        .font(AppTheme.ScaledFont.body)
                    if !lesson.subject.isEmpty {
                        Text("(\(lesson.subject))")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if resolvedLessons.isEmpty {
                Text("Lessons not found")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, AppTheme.Spacing.verySmall)
    }

    private var resolvedLessons: [CDLesson] {
        lessonIDs.compactMap { id in
            let descriptor = { let r = NSFetchRequest<CDLesson>(entityName: "Lesson"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); r.fetchLimit = 1; return r }()
            return viewContext.safeFetchFirst(descriptor)
        }
    }
}
