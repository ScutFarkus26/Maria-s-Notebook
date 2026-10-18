import SwiftUI
import CoreData

/// The Resources files linked to a lesson: by the lesson itself, or by its
/// area. A lesson's Files section lists them under its attachments.
enum LessonLinkedResources {

    /// The resources that might link to the lesson: their link fields mention
    /// its id or its area. `matching` makes the exact call; this keeps the
    /// fetch from reading every resource.
    static func fetchRequest(lessonID: UUID?, area: String) -> NSFetchRequest<CDResource> {
        let request = CDFetchRequest(CDResource.self)
        var clauses: [NSPredicate] = []
        if let lessonID {
            clauses.append(NSPredicate(format: "linkedLessonIDs CONTAINS[c] %@", lessonID.uuidString))
        }
        let trimmedArea = area.trimmingCharacters(in: .whitespaces)
        if !trimmedArea.isEmpty {
            clauses.append(NSPredicate(format: "linkedAreas CONTAINS[c] %@", trimmedArea))
        }
        request.predicate = clauses.isEmpty
            ? NSPredicate(value: false)
            : NSCompoundPredicate(orPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDResource.title, ascending: true)]
        return request
    }

    /// The resources linked to the lesson by its id, or to its area by name
    /// (trimmed, any case), once each, in the order given.
    static func matching(_ resources: [CDResource], lessonID: UUID?, area: String) -> [CDResource] {
        let idString = lessonID?.uuidString.lowercased()
        let areaKey = area.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<UUID>()
        return resources.filter { resource in
            guard let resourceID = resource.id, !resource.isDeleted else { return false }
            let linkedIDs = resource.linkedLessonIDs
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let linkedAreas = resource.linkedAreas
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let isLinked = (idString.map(linkedIDs.contains) ?? false)
                || (!areaKey.isEmpty && linkedAreas.contains(areaKey))
            return isLinked && seen.insert(resourceID).inserted
        }
    }
}

/// The Linked Resources group of a lesson's Files section: one row per
/// resource, opening its detail (a window on the Mac, a sheet elsewhere).
struct LessonLinkedResourcesGroup: View {
    let resources: [CDResource]

    @State private var openResource: CDResource?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Resources")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(resources, id: \.objectID) { resource in
                Button {
                    open(resource)
                } label: {
                    row(for: resource)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the resource")
            }
        }
        #if os(iOS)
        .sheet(item: $openResource) { resource in
            ResourceDetailView(resource: resource)
        }
        #endif
    }

    private func row(for resource: CDResource) -> some View {
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
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func open(_ resource: CDResource) {
        #if os(macOS)
        guard let id = resource.id else { return }
        openWindow(id: "ResourceDetailWindow", value: id)
        #else
        openResource = resource
        #endif
    }
}
