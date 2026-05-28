// ProgressDashboardView.swift
// Per-student progression map: each student is a heading; under each student the subjects
// they've started (lesson.area); under each subject the area-rows (lesson.sequence) showing
// where they are in the progression as a row of status pills.
// Tapping a sequence row opens StudentSequenceDetailSheet with related work, presentations
// given, and notes for that student in that sequence.

import SwiftUI
import CoreData

struct ProgressDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = ProgressDashboardViewModel()
    @State private var detailTarget: StudentSequenceDetailTarget?

    // Reload on assignment / work mutations.
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)])
    private var assignmentsForChange: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.id, ascending: true)])
    private var workForChange: FetchedResults<CDWorkModel>

    private var changeToken: Int { assignmentsForChange.count &+ workForChange.count }

    var body: some View {
        content
            .navigationTitle("Progress")
            .searchable(text: $viewModel.searchText, prompt: "Search students")
            .onAppear { viewModel.loadData(context: viewContext) }
            .onChange(of: changeToken) { _, _ in viewModel.loadData(context: viewContext) }
            .sheet(item: $detailTarget) { target in
                StudentSequenceDetailSheet(target: target) {
                    detailTarget = nil
                }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
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
                levelFilterRow
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                summaryRow
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredCards) { card in
                        ProgressDashboardStudentCard(card: card) { sequence in
                            detailTarget = StudentSequenceDetailTarget(
                                studentID: card.id,
                                studentName: card.fullName,
                                area: sequence.area,
                                sequence: sequence.sequence,
                                lessonIDs: sequence.pills.map(\.lessonID)
                            )
                        }
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
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let cards = viewModel.filteredCards
        let totalSequences = cards.reduce(0) { $0 + $1.sequenceCount }
        return HStack(spacing: 0) {
            Text("\(cards.count)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" students · ")
                .foregroundStyle(.tertiary)
            Text("\(totalSequences)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" active areas")
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
            Text("Present lessons or assign work to students to see their progress here.")
        }
    }
}
