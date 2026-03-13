// CosmicMapRootView.swift
// Top-level view showing the Five Great Lessons curriculum map.
// Displays cards for each Great Lesson with lesson counts and student coverage.

import SwiftUI
import SwiftData

struct CosmicMapRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CosmicMapViewModel()

    // Change detection
    @Query(sort: [SortDescriptor(\Lesson.id)])
    private var lessonsForChange: [Lesson]
    private var lessonChangeToken: Int { lessonsForChange.count }

    var body: some View {
        content
            .navigationTitle("Cosmic Map")
            .searchable(text: $viewModel.searchText, prompt: "Search lessons")
            .onAppear { viewModel.loadData(context: modelContext) }
            .onChange(of: lessonChangeToken) { _, _ in
                viewModel.loadData(context: modelContext)
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.totalLessonCount == 0 {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary stats
                summaryRow
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Great Lesson cards
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.greatLessonCards) { cardData in
                        NavigationLink {
                            GreatLessonDetailView(
                                greatLesson: cardData.greatLesson,
                                lessons: viewModel.filteredLessons(for: cardData.greatLesson)
                            )
                        } label: {
                            GreatLessonCard(data: cardData)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.totalLessonCount)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" total lessons · ")
                .foregroundStyle(.tertiary)
            Text("\(viewModel.taggedPercentage)%")
                .fontWeight(.semibold)
                .foregroundStyle(viewModel.taggedPercentage > 50 ? AppColors.success : AppColors.warning)
            Text(" tagged")
                .foregroundStyle(.tertiary)
            if viewModel.untaggedCount > 0 {
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.untaggedCount) untagged")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lessons", systemImage: "globe.americas")
        } description: {
            Text("Add lessons to your curriculum to see them mapped to the Five Great Lessons.")
        }
    }
}
