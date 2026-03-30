// DevelopmentalTraitsView.swift
// Per-student timeline view showing developmental characteristic observations over time.
// Displays trait cards with counts and a chronological observation list.

import SwiftUI
import SwiftData

struct DevelopmentalTraitsView: View {
    let studentID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DevelopmentalTraitsViewModel()

    var body: some View {
        content
            .navigationTitle("Developmental Traits")
            .onAppear {
                viewModel.studentID = studentID
                viewModel.loadData(context: modelContext)
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.totalTraitObservations == 0 {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Time range picker
                timeRangeRow
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Summary
                summaryRow
                    .padding(.horizontal)

                // Trait cards
                traitCardsSection
                    .padding(.horizontal)

                // Recent observations
                if !viewModel.recentObservations.isEmpty {
                    recentObservationsSection
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Time Range

    private var timeRangeRow: some View {
        HStack(spacing: 8) {
            ForEach(ObservationTimeRange.allCases) { range in
                timeRangeCapsule(range)
            }
            Spacer()
        }
    }

    private func timeRangeCapsule(_ range: ObservationTimeRange) -> some View {
        let isSelected = viewModel.timeRange == range
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.timeRange = range
                viewModel.loadData(context: modelContext)
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

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.totalTraitObservations)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" trait observations")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Trait Cards

    private var traitCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Characteristics")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.traitCards) { card in
                    DevelopmentalTraitCard(data: card)
                }
            }
        }
    }

    // MARK: - Recent Observations

    private var recentObservationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Observations")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.recentObservations) { observation in
                    observationRow(observation)
                }
            }
        }
    }

    private func observationRow(_ observation: TraitObservation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date
            Text(observation.date, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Body preview
            Text(observation.bodyPreview)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Trait badges
            FlowLayout(spacing: 4) {
                ForEach(observation.traits) { trait in
                    HStack(spacing: 3) {
                        Image(systemName: trait.icon)
                            .font(.system(size: 8))
                        Text(trait.rawValue)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(trait.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(trait.color.opacity(UIConstants.OpacityConstants.medium))
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Developmental Observations", systemImage: "brain.head.profile")
        } description: {
            Text("Tag observations with developmental characteristics to track patterns over time.")
        }
    }
}
