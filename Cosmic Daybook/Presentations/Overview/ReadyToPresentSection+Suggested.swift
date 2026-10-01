// ReadyToPresentSection+Suggested.swift
// The Suggest flag.
//
// Every other flag is a filter, and its own name is the whole explanation: a
// row under Overdue is there because it is overdue. Suggest is the one flag
// whose contents come out of a score, so it is the one that has to show its
// work — a ranking a guide cannot account for is one they have to
// second-guess, and second-guessing it is slower than not having it.
//
// Its rows are presentations, not lessons: the score ranks each group on its
// own merits, so two groups of one lesson can sit at different ranks.

import SwiftUI
import CoreData

extension ReadyToPresentSection {

    private static let rankingExplanation = """
        Ranked by who has gone longest without a presentation, how long the \
        lesson has waited here, how much work those children already have \
        open, and whether it changes the area. A child who is already booked \
        for a lesson doesn't count toward the wait.
        """

    @ViewBuilder
    func suggestedNextContent(_ slices: ReadyToPresentSlices) -> some View {
        let suggestions = suggestedNextSlice(among: slices.ready)
        if suggestions.isEmpty {
            emptyState(
                "No Suggestions", systemImage: "sparkles",
                description: "No ready presentations match the current filters."
            )
        } else {
            let context = renderContext(state: .suggestedNext, slices: slices)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                stateExplanation(Self.rankingExplanation)
                // Not lazy, so a deep link can scroll to any row (see `backlogList`).
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestedRow(rank: index + 1, suggestion: suggestion, context: context)
                        Divider()
                            .padding(.leading, AppTheme.Spacing.small)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.small)
            }
        }
    }

    /// The row, and under it the reason it sits where it sits.
    private func suggestedRow(
        rank: Int,
        suggestion: SuggestedPresentation,
        context: BacklogRenderContext
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            singleLessonRow(suggestion.assignment, context: context)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xxsmall) {
                Text("\(rank).")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(suggestion.rationale.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.verySmall)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Suggestion \(rank). \(suggestion.rationale.summary)")
        }
    }
}
