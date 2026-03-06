import SwiftUI
import SwiftData

/// Displays resources linked to a specific lesson (by ID or subject).
/// Used inside LessonDetailView to cross-surface related resources.
struct RelatedResourcesSection: View {
    let lessonID: UUID
    let lessonSubject: String

    @Query(sort: \Resource.title) private var allResources: [Resource]
    @State private var selectedResource: Resource?

    private var relatedResources: [Resource] {
        let idString = lessonID.uuidString
        var results: [Resource] = []
        var seen = Set<UUID>()

        for resource in allResources {
            // Check if this resource is directly linked to the lesson
            let linkedIDs = resource.linkedLessonIDs
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            if linkedIDs.contains(idString) {
                if seen.insert(resource.id).inserted {
                    results.append(resource)
                }
                continue
            }

            // Check if this resource is linked to the same subject
            if !lessonSubject.trimmingCharacters(in: .whitespaces).isEmpty {
                let linkedSubjects = resource.linkedSubjects
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

                if linkedSubjects.contains(lessonSubject.trimmingCharacters(in: .whitespaces).lowercased()) {
                    if seen.insert(resource.id).inserted {
                        results.append(resource)
                    }
                }
            }
        }

        return results
    }

    var body: some View {
        if !relatedResources.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                HStack(spacing: AppTheme.Spacing.small + 2) {
                    Image(systemName: "tray.2")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Related Resources")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    ForEach(relatedResources) { resource in
                        Button {
                            selectedResource = resource
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: resource.category.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)

                                Text(resource.title)
                                    .font(AppTheme.ScaledFont.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

                                Text(resource.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, AppTheme.Spacing.verySmall)
            .sheet(item: $selectedResource) { resource in
                ResourceDetailView(resource: resource)
            }
        }
    }
}
