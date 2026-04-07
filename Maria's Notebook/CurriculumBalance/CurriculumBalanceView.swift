// CurriculumBalanceView.swift
// Top-level view showing curriculum subject distribution and gap analysis.
// Supports classroom-wide and per-student scopes with configurable time ranges.
// Design follows ProgressDashboardView: filters, summary, cards/charts.

import SwiftUI
import CoreData

struct CurriculumBalanceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = CurriculumBalanceViewModel()
    @State private var selectedGapSubjectName: String?

    // Change detection to trigger reload when assignments change
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)]) private var assignmentsForChange: FetchedResults<CDLessonAssignment>

    private var assignmentChangeToken: Int { assignmentsForChange.count }

    var body: some View {
        content
            .navigationTitle("Curriculum Balance")
            .searchable(
                text: $viewModel.searchText,
                prompt: viewModel.scope == .perStudent ? "Search students" : "Search subjects"
            )
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: assignmentChangeToken) { _, _ in
                viewModel.loadData(context: viewContext)
            }
            .onChange(of: viewModel.timeRange) { _, _ in
                viewModel.loadData(context: viewContext)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.classroomDistribution.isEmpty && viewModel.studentCards.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Time range picker
                timeRangeRow
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Scope toggle
                scopeToggle
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                // Summary
                summaryRow
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                // Content based on scope
                if viewModel.scope == .classroom {
                    classroomContent
                        .padding(.horizontal)
                } else {
                    perStudentContent
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Time Range Picker

    private var timeRangeRow: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsTimeRange.allCases) { range in
                timeRangeCapsule(range)
            }
            Spacer()
        }
    }

    private func timeRangeCapsule(_ range: AnalyticsTimeRange) -> some View {
        let isSelected = viewModel.timeRange == range
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.timeRange = range
            }
        } label: {
            Text(range.rawValue)
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

    // MARK: - Scope Toggle

    private var scopeToggle: some View {
        Picker("Scope", selection: $viewModel.scope) {
            ForEach(AnalyticsScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.totalLessons)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" lessons · ")
                .foregroundStyle(.tertiary)
            Text("\(viewModel.uniqueSubjectCount)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" subjects")
                .foregroundStyle(.tertiary)
            if !viewModel.classroomGaps.isEmpty {
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.classroomGaps.count) gaps")
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.warning)
            }
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Classroom Content

    private var classroomContent: some View {
        VStack(spacing: 16) {
            SubjectDistributionChart(data: viewModel.classroomDistribution)
            SubjectWeeklyTrendChart(data: viewModel.weeklyTrends)
            CurriculumBalanceGapSection(gaps: viewModel.classroomGaps) { gap in
                selectedGapSubjectName = gap.subject
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedGapSubjectName != nil },
            set: { if !$0 { selectedGapSubjectName = nil } }
        )) {
            if let subject = selectedGapSubjectName {
                GapActionSheet(subject: subject, context: viewContext)
            }
        }
    }

    // MARK: - Per-CDStudent Content

    private var perStudentContent: some View {
        VStack(spacing: 0) {
            // Level filter
            levelFilterRow
                .padding(.bottom, 12)

            // CDStudent count
            HStack(spacing: 0) {
                Text("\(viewModel.filteredStudentCards.count)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(" students with lessons")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption)
            .padding(.bottom, 12)

            // CDStudent cards
            LazyVStack(spacing: 10) {
                ForEach(viewModel.filteredStudentCards) { card in
                    CurriculumBalanceStudentCard(card: card)
                }
            }
        }
    }

    // MARK: - Level Filter

    private var levelFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(LevelFilter.allCases) { filter in
                levelFilterCapsule(filter)
            }
            Spacer()
        }
    }

    private func levelFilterCapsule(_ filter: LevelFilter) -> some View {
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

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Curriculum Data", systemImage: SFSymbol.Chart.chartPie)
        } description: {
            Text("Present lessons to students to see curriculum balance analytics here.")
        }
    }
}
