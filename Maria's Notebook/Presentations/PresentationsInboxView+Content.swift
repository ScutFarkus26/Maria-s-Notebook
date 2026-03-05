// PresentationsInboxView+Content.swift
// Content sections extracted from PresentationsInboxView

import SwiftUI

extension PresentationsInboxView {
    // MARK: - Content Views

    @ViewBuilder
    var presentationsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {

                // 1. BLOCKED / WAITING SECTION
                if !filteredAndSortedBlockedLessons.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Label("On Deck (Waiting for Work)", systemImage: "hourglass")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.compact)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: AppTheme.Spacing.small) {
                                ForEach(filteredAndSortedBlockedLessons, id: \.id) { la in
                                    inboxRow(la, blockingWork: getBlockingWork(la))
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.compact)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.compact)
                }

                // 2. READY SECTION
                if filteredAndSortedReadyLessons.isEmpty {
                    if filteredAndSortedBlockedLessons.isEmpty {
                        ContentUnavailableView(
                            "All Caught Up", systemImage: "checkmark.circle",
                            description: Text("No unscheduled presentations.")
                        )
                            .padding(.top, AppTheme.Spacing.large + AppTheme.Spacing.medium)
                    } else {
                        Text("All planned presentations are waiting on work.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
                    }
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.small)
                    ], alignment: .leading, spacing: AppTheme.Spacing.small) {
                        ForEach(filteredAndSortedReadyLessons, id: \.id) { la in
                            inboxRow(la)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.compact)
                }
            }
            .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
        }
    }
}
