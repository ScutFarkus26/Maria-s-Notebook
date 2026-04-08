// ThreeYearCycleView.swift
// Root view for the Three-Year Cycle Bird's-Eye View.

import SwiftUI
import CoreData

struct ThreeYearCycleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = ThreeYearCycleViewModel()

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)],
        predicate: NSPredicate(
            format: "stateRaw == %@",
            LessonAssignmentState.presented.rawValue
        )
    ) private var presentedAssignments: FetchedResults<CDLessonAssignment>

    private var changeToken: Int { presentedAssignments.count }

    var body: some View {
        content
            .navigationTitle("Three-Year Cycle")
            .searchable(text: $viewModel.searchText, prompt: "Search students")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in viewModel.loadData(context: viewContext) }
            .onChange(of: viewModel.levelFilter) { _, _ in viewModel.loadData(context: viewContext) }
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
            VStack(spacing: 12) {
                // Filters
                filterBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Summary row
                summaryRow
                    .padding(.horizontal)

                // Year filter capsules
                yearFilterBar
                    .padding(.horizontal)

                // Sort picker
                sortPicker
                    .padding(.horizontal)

                // Student cards
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredCards) { card in
                        NavigationLink(value: card.id) {
                            ThreeYearCycleStudentCard(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationDestination(for: UUID.self) { studentID in
            if let card = viewModel.studentCards.first(where: { $0.id == studentID }) {
                ThreeYearCycleDetailView(card: card)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        Picker("Level", selection: $viewModel.levelFilter) {
            ForEach(LevelFilter.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Year Filter

    private var yearFilterBar: some View {
        HStack(spacing: 8) {
            yearCapsule(nil, label: "All")
            ForEach(CycleYear.selectableCases) { year in
                yearCapsule(year, label: year.displayName)
            }
            Spacer()
        }
    }

    private func yearCapsule(_ year: CycleYear?, label: String) -> some View {
        let isSelected = viewModel.yearFilter == year
        let color = year?.color ?? .primary
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.yearFilter = year
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)

                if let year, let count = viewModel.yearCounts[year] {
                    Text("\(count)")
                        .font(.system(size: 9))
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? color : color.opacity(UIConstants.OpacityConstants.light))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.studentCards.count)")
                .fontWeight(.semibold)
            Text(" students")
                .foregroundStyle(.tertiary)
            Text(" · ")
                .foregroundStyle(.tertiary)
            Text("\(Int(viewModel.averageCoverage * 100))%")
                .fontWeight(.semibold)
            Text(" avg coverage")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Sort Picker

    private var sortPicker: some View {
        HStack {
            Text("Sort by")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(CycleSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Students", systemImage: "person.3")
        } description: {
            Text("Enroll students and present lessons to see their three-year cycle progress.")
        }
    }
}
