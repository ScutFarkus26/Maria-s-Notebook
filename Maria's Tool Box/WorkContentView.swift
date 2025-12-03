import SwiftUI

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
    
    private var sectionOrder: [String] {
        WorkGroupingService.sectionOrder(for: grouping)
    }
    
    private func itemsForSection(_ key: String) -> [WorkModel] {
        WorkGroupingService.itemsForSection(
            key,
            grouping: grouping,
            works: works,
            linkedDate: lookupService.linkedDate
        )
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
    }
}
