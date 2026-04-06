// PresentationsInboxView+Content.swift
// Content sections extracted from PresentationsInboxView

import SwiftUI
import CoreData
import OSLog

extension PresentationsInboxView {
    // MARK: - On Deck Card with Readiness

    @ViewBuilder
    func onDeckCard(_ la: CDLessonAssignment, blockingWork: [UUID: CDWorkModel]) -> some View {
        let result = la.id.flatMap { blockingResults[$0] }
        let readyCount = result?.readyStudentIDs.count ?? 0
        let totalCount = la.resolvedStudentIDs.count
        let hasPartialReadiness = readyCount > 0 && readyCount < totalCount

        VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
            inboxRow(la, blockingWork: blockingWork)

            // Readiness badge
            if totalCount > 1, let result {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    Text("\(readyCount) of \(totalCount) ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hasPartialReadiness ? .orange : .secondary)

                    Spacer()

                    if hasPartialReadiness {
                        Button {
                            splitReadyToInbox(la, result: result)
                        } label: {
                            Text("Move Ready")
                                .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.verySmall)
            }
        }
    }

    private func splitReadyToInbox(_ la: CDLessonAssignment, result: BlockingAlgorithmEngine.BlockingCheckResult) {
        let readyIDs = result.readyStudentIDs
        guard !readyIDs.isEmpty else { return }

        guard let ctx = la.managedObjectContext else { return }
        PresentationSplitService.splitReadyStudents(
            from: la,
            readyStudentIDs: readyIDs,
            asDraft: true,
            context: ctx
        )
        do {
            try ctx.save()
        } catch {
            Logger.presentations.error("Failed to save after split: \(error)")
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    var presentationsContent: some View {
        ScrollViewReader { proxy in
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
                                        onDeckCard(la, blockingWork: getBlockingWork(la))
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
                                    .id(la.id)
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: UIConstants.CornerRadius.medium,
                                            style: .continuous
                                        )
                                        .stroke(Color.accentColor, lineWidth: suggestedLessonID == la.id ? 2.5 : 0)
                                        .shadow(
                                            color: .accentColor.opacity(suggestedLessonID == la.id ? 0.4 : 0),
                                            radius: 6
                                        )
                                    )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.compact)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.xsmall)
            }
            .onChange(of: suggestedLessonID) {
                if let id = suggestedLessonID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}
