import SwiftUI

// MARK: - Notebook Stats

/// Troubleshooting › Notebook at a glance: how many records of each kind the notebook holds.
struct SettingsNotebookStatsView: View {
    var statsViewModel: SettingsStatsViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var overviewColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.medium), count: columnCount)
    }

    var body: some View {
        SettingsGroup(.notebookStats) {
            VStack(spacing: AppTheme.Spacing.medium) {
                DatabaseTotalSummary(totalRecords: statsViewModel.totalRecordsCount)

                ForEach(NotebookRecordSection.allCases) { section in
                    DatabaseStatsSubsection(
                        title: section.title,
                        systemImage: section.systemImage,
                        count: statsViewModel.total(of: section)
                    ) {
                        LazyVGrid(columns: overviewColumns, spacing: AppTheme.Spacing.medium) {
                            ForEach(section.kinds) { kind in
                                StatCard(
                                    title: kind.title,
                                    value: statsViewModel.count(of: kind).formatted(),
                                    subtitle: statsViewModel.detail(for: kind),
                                    systemImage: kind.systemImage
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
