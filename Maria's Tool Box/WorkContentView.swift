import SwiftUI
import SwiftData

struct WorkContentView: View {
    let works: [WorkModel]
    let grouping: WorkFilters.Grouping
    let lookupService: WorkLookupService
    let onTapWork: (WorkModel) -> Void
    let onToggleComplete: (WorkModel) -> Void
    
    var body: some View {
        if grouping == .none {
            WorkCardsGridView(
                works: works,
                studentsByID: lookupService.studentsByID,
                lessonsByID: lookupService.lessonsByID,
                studentLessonsByID: lookupService.studentLessonsByID,
                onTapWork: onTapWork,
                onToggleComplete: onToggleComplete
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GroupedWorksView(
                works: works,
                grouping: grouping,
                lookupService: lookupService,
                onTapWork: onTapWork,
                onToggleComplete: onToggleComplete
            )
        }
    }
}

struct GroupedWorksView: View {
    let works: [WorkModel]
    let grouping: WorkFilters.Grouping
    let lookupService: WorkLookupService
    let onTapWork: (WorkModel) -> Void
    let onToggleComplete: (WorkModel) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var groupedIDs: [String: [UUID]] = [:]
    private var worksByID: [UUID: WorkModel] { Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0) }) }
    
    private var sectionOrder: [String] {
        WorkGroupingService.sectionOrder(for: grouping)
    }
    
    private func itemsForSection(_ key: String) -> [WorkModel] {
        if grouping == .checkIns {
            // Use async-computed groups of IDs and map back to models for display
            let ids = groupedIDs[key] ?? []
            return ids.compactMap { worksByID[$0] }
        } else {
            return WorkGroupingService.itemsForSection(
                key,
                grouping: grouping,
                works: works,
                linkedDate: lookupService.linkedDate
            )
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sectionOrder, id: \.self) { key in
                    let items = itemsForSection(key)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: WorkGroupingService.sectionIcon(for: key))
                                    .foregroundStyle(.secondary)
                                Text(key)
                                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            
                            WorkCardsGridView(
                                works: items,
                                studentsByID: lookupService.studentsByID,
                                lessonsByID: lookupService.lessonsByID,
                                studentLessonsByID: lookupService.studentLessonsByID,
                                onTapWork: onTapWork,
                                onToggleComplete: onToggleComplete,
                                embedInScrollView: false,
                                hideTypeBadge: (grouping == .type)
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: grouping.rawValue + works.map { $0.id.uuidString }.joined(separator: ",")) {
            if grouping == .checkIns {
                let actor = WorkGroupingServiceActor(modelContainer: modelContext.container)
                let ids = works.map { $0.id }
                do {
                    let result = try await WorkGroupingService.groupByCheckIns(workIDs: ids, using: actor)
                    groupedIDs = result
                } catch {
                    groupedIDs = [:]
                }
            } else {
                groupedIDs = [:]
            }
        }
    }
}

