// ProgressionRootView.swift
// Landing page for the Progression feature -- shows subject/group cards.

import SwiftUI
import SwiftData

/// Landing page that shows subject/group cards for groups with student activity.
struct ProgressionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressionRootViewModel()
    @State private var searchText = ""

    private var filteredSummaries: [GroupSummary] {
        guard !searchText.isEmpty else { return viewModel.groupSummaries }
        let query = searchText.lowercased()
        return viewModel.groupSummaries.filter {
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    /// Group summaries by subject for sectioned display
    private var groupedBySubject: [(subject: String, summaries: [GroupSummary])] {
        let dict = Dictionary(grouping: filteredSummaries) { $0.subject }
        return dict.keys.sorted().map { key in
            (subject: key, summaries: (dict[key] ?? []).sorted { $0.group < $1.group })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading progression data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.groupSummaries.isEmpty {
                    emptyState
                } else {
                    scrollContent
                }
            }
            .navigationTitle("Progression")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .searchable(text: $searchText, prompt: "Search subjects or groups")
            .onAppear {
                viewModel.loadData(context: modelContext)
            }
            .refreshable {
                viewModel.loadData(context: modelContext)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Progression Data", systemImage: SFSymbol.Chart.chartLine)
        } description: {
            Text("Once you give lessons and assign work, progression data will appear here.")
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groupedBySubject, id: \.subject) { section in
                    sectionView(subject: section.subject, summaries: section.summaries)
                }
            }
            .padding()
        }
    }

    // MARK: - Section

    private func sectionView(subject: String, summaries: [GroupSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColors.color(forSubject: subject))
                    .frame(width: 10, height: 10)
                Text(subject)
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 16)], spacing: 16) {
                ForEach(summaries) { summary in
                    Button {
                        AppRouter.shared.navigateToChecklist(subject: summary.subject, group: summary.group)
                    } label: {
                        GroupSummaryCard(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Group Summary Card

private struct GroupSummaryCard: View {
    let summary: GroupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Color bar + group name
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.color(forSubject: summary.subject))
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.group)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(summary.lessonCount) lessons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Stats row
            HStack(spacing: 16) {
                statBadge(count: summary.studentCount, label: "students", icon: "person.2", color: .primary)
                if summary.activeWorkCount > 0 {
                    statBadge(count: summary.activeWorkCount, label: "active work", icon: "tray.full", color: .blue)
                }
            }

            // Ready / attention indicators
            HStack(spacing: 12) {
                if summary.studentsReadyForNext > 0 {
                    Label("\(summary.studentsReadyForNext) ready for next", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                }
                if summary.studentsNeedingAttention > 0 {
                    Label("\(summary.studentsNeedingAttention) need attention", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }

            // Furthest lesson
            if let furthest = summary.furthestLessonName {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Furthest: \(furthest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ProgressionRootView()
        .previewEnvironment()
}
