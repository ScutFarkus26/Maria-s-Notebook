// ReadyToPresentSection+Suggested.swift
// The Suggested Next pill.
//
// Every other pill is a slice, and its own name is the whole explanation: a
// card under Overdue is there because it is overdue. Suggested Next is the one
// pill whose contents come out of a score, so it is the one pill that has to
// show its work — a ranking a guide cannot account for is one they have to
// second-guess, and second-guessing it is slower than not having it.

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
    var suggestedNextContent: some View {
        let suggestions = suggestedNextSlice
        if suggestions.isEmpty {
            ContentUnavailableView(
                "No suggestions", systemImage: "sparkles",
                description: Text("No ready presentations match the current filters.")
            )
            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text(Self.rankingExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.compact)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small, alignment: .topLeading),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small, alignment: .topLeading),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.small, alignment: .topLeading)
                ], alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestedCard(rank: index + 1, suggestion: suggestion)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
            }
            .padding(.top, AppTheme.Spacing.compact)
        }
    }

    /// The card, and under it the reason it sits where it sits. The rank is
    /// spelled out because five cards wrap across three columns, and reading
    /// order alone stops carrying the order once it wraps.
    private func suggestedCard(rank: Int, suggestion: SuggestedPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            readyGridItem(suggestion.assignment)

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
            .padding(.horizontal, AppTheme.Spacing.verySmall)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Suggestion \(rank). \(suggestion.rationale.summary)")
        }
    }
}
