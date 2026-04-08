// FridayReviewView.swift
// Root view for the Friday Review Ritual — end-of-week reflection and Monday planning.

import SwiftUI
import CoreData

struct FridayReviewView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = FridayReviewViewModel()

    // Change detection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)],
        predicate: NSPredicate(
            format: "createdAt >= %@",
            Calendar.current.date(byAdding: .day, value: -7, to: Date())! as NSDate
        )
    ) private var recentNotes: FetchedResults<CDNote>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)],
        predicate: NSPredicate(
            format: "statusRaw IN %@",
            [WorkStatus.active.rawValue, WorkStatus.review.rawValue]
        )
    ) private var activeWork: FetchedResults<CDWorkModel>

    private var changeToken: Int { recentNotes.count + activeWork.count }

    var body: some View {
        content
            .navigationTitle("Friday Review")
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
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Level filter
                levelFilterBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Week Summary
                if let summary = viewModel.weekSummary {
                    FridayReviewWeekSummarySection(summary: summary)
                        .padding(.horizontal)
                }

                // Unobserved Students
                FridayReviewUnobservedSection(students: viewModel.unobservedStudents)
                    .padding(.horizontal)

                // Needs Follow-Up
                if !viewModel.followUpItems.isEmpty {
                    FridayReviewFollowUpSection(items: viewModel.followUpItems)
                        .padding(.horizontal)
                }

                // Stale Work
                if !viewModel.staleWorkItems.isEmpty {
                    FridayReviewStaleWorkSection(items: viewModel.staleWorkItems)
                        .padding(.horizontal)
                }

                // Monday Priorities
                if !viewModel.mondayPriorities.isEmpty {
                    FridayReviewMondayPrioritiesSection(priorities: viewModel.mondayPriorities)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Level Filter

    private var levelFilterBar: some View {
        Picker("Level", selection: $viewModel.levelFilter) {
            ForEach(LevelFilter.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
}
