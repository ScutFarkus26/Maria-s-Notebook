// LessonFrequencyView.swift
// Top-level view showing per-student weekly lesson counts.
// AMI best practices recommend 5–7 lessons per student per week.
// Design follows ProgressDashboardView: level filters, summary row, student cards.

import SwiftUI
import CoreData

struct LessonFrequencyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = LessonFrequencyViewModel()

    // Change detection to trigger reload when assignments change
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)]) private var assignmentsForChange: FetchedResults<CDLessonAssignment>

    private var assignmentChangeToken: Int { assignmentsForChange.count }

    var body: some View {
        content
            .navigationTitle("Lesson Frequency")
            .searchable(text: $viewModel.searchText, prompt: "Search students")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: assignmentChangeToken) { _, _ in
                viewModel.loadData(context: viewContext)
            }
            .onChange(of: viewModel.selectedWeekOffset) { _, _ in
                viewModel.loadData(context: viewContext)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.studentCards.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Week picker
                weekPickerRow
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Level filter capsule pills
                levelFilterRow
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                // Summary stat cards
                summaryStatsRow
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                // CDStudent cards
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredCards) { card in
                        LessonFrequencyStudentRow(
                            card: card,
                            targetRange: viewModel.targetRange
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Week Picker

    private var weekPickerRow: some View {
        HStack {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.selectedWeekOffset -= 1
                }
            } label: {
                Image(systemName: SFSymbol.Navigation.chevronLeft)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekLabel)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.primary)

                if viewModel.selectedWeekOffset == 0 {
                    Text("This Week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.selectedWeekOffset += 1
                }
            } label: {
                Image(systemName: SFSymbol.Navigation.chevronRight)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.selectedWeekOffset >= 0 ? .quaternary : .secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedWeekOffset >= 0)
        }
    }

    // MARK: - Level Filter

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

    // MARK: - Summary Stats

    private var summaryStatsRow: some View {
        HStack(spacing: 12) {
            FrequencyStatCard(
                title: "Class Avg",
                value: String(format: "%.1f", viewModel.classAverage),
                icon: SFSymbol.Chart.chartBar,
                color: .blue
            )

            FrequencyStatCard(
                title: "Below Target",
                value: "\(viewModel.belowTargetCount)",
                icon: "exclamationmark.triangle.fill",
                color: AppColors.destructive
            )

            FrequencyStatCard(
                title: "On Target",
                value: "\(viewModel.onTargetCount)",
                icon: SFSymbol.Action.checkmarkCircleFill,
                color: AppColors.success
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No CDLesson Data", systemImage: SFSymbol.Chart.chartBar)
        } description: {
            Text("Present lessons to students to see weekly frequency data here.")
        }
    }
}

// MARK: - Stat Card

private struct FrequencyStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppTheme.ScaledFont.captionSmall)
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(AppTheme.ScaledFont.header)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(UIConstants.OpacityConstants.light))
        .cornerRadius(UIConstants.CornerRadius.large)
    }
}
