// ProgressDashboardView.swift
// Top-level view showing all students' progress across subjects and categories.
// Design: Linear-inspired clean layout, Things 3 capsule filters, generous whitespace.

import SwiftUI
import SwiftData

struct ProgressDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressDashboardViewModel()

    // Sheet state
    @State private var selectedLessonAssignment: LessonAssignment?
    @State private var selectedWorkID: UUID?

    // Change detection to trigger reload
    @Query(sort: [SortDescriptor(\LessonAssignment.id)])
    private var assignmentsForChange: [LessonAssignment]

    private var assignmentChangeToken: Int { assignmentsForChange.count }

    var body: some View {
        content
            .navigationTitle("Progress")
            .searchable(text: $viewModel.searchText, prompt: "Search students")
            .onAppear { viewModel.loadData(context: modelContext) }
            .onChange(of: assignmentChangeToken) { _, _ in
                viewModel.loadData(context: modelContext)
            }
            .sheet(item: $selectedLessonAssignment) { la in
                PresentationDetailView(lessonAssignment: la) {
                    selectedLessonAssignment = nil
                    viewModel.loadData(context: modelContext)
                }
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
            }
            .sheet(id: $selectedWorkID) { id in
                WorkDetailView(workID: id) {
                    selectedWorkID = nil
                    viewModel.loadData(context: modelContext)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredCards.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Capsule filter pills
                levelFilterRow
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Summary line
                summaryRow
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredCards) { card in
                        ProgressDashboardStudentCard(
                            card: card,
                            onTapPreviousLesson: { assignmentID in
                                selectedLessonAssignment = viewModel.lessonAssignmentsByID[assignmentID]
                            },
                            onTapNextLesson: { assignmentID in
                                selectedLessonAssignment = viewModel.lessonAssignmentsByID[assignmentID]
                            },
                            onTapWork: { workID in
                                selectedWorkID = workID
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Filter Pills

    private var levelFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(LevelFilter.allCases) { filter in
                filterCapsule(filter)
            }
            Spacer()
        }
    }

    private func filterCapsule(_ filter: LevelFilter) -> some View {
        let isSelected = viewModel.levelFilter == filter
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.levelFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let cards = viewModel.filteredCards
        let totalCategories = cards.reduce(0) { $0 + $1.categories.count }
        return HStack(spacing: 0) {
            Text("\(cards.count)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" students · ")
                .foregroundStyle(.tertiary)
            Text("\(totalCategories)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" active subjects")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Progress Data", systemImage: "person.text.rectangle")
        } description: {
            Text("Present lessons to students to see their progress here.")
        }
    }
}
