// StudentHistoryTab.swift
// Past Learning: the sequences the child has mastered every lesson of, and
// her finished projects. A completed sequence is read from her presentation
// record (`SequenceStanding`), not stored (2026-11-03).

import SwiftUI
import CoreData

struct StudentHistoryTab: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDProject.createdAt, ascending: false)])
    private var allProjects: FetchedResults<CDProject>

    @State private var finishedStandings: [SequenceStanding] = []
    @State private var selectedStanding: SequenceStanding?
    @State private var selectedProject: CDProject?

    private var finishedProjects: [CDProject] {
        let sid = student.id?.uuidString ?? ""
        return allProjects.filter { $0.memberStudentIDsArray.contains(sid) && !$0.isActive }
    }

    // Celebration colors for completed sequences
    private let celebrationColors: [Color] = [.green, .blue, .purple, .orange, .pink, .teal]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Past Projects Section
                if !finishedProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Past Projects", systemImage: SFSymbol.Education.bookClosedFill)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(finishedProjects) { project in
                            finishedProjectRow(project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProject = project
                                }
                        }
                    }
                }

                // Completed Sequences Section
                if finishedStandings.isEmpty {
                    if finishedProjects.isEmpty {
                        emptyStateView
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text("Completed Sequences")
                                .font(.headline)
                        }
                        .padding(.horizontal, 4)

                        ForEach(Array(finishedStandings.enumerated()), id: \.element.id) { index, standing in
                            finishedSequenceCard(standing: standing, colorIndex: index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedStanding = standing
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A mark made elsewhere finishes or reopens a sequence.
        .onPresentationDataChangeWhenVisible(
            of: ["LessonPresentation"],
            in: viewContext,
            catchUpOnAppear: false
        ) {
            loadStandings()
        }
        .onAppear {
            loadStandings()
        }
        .sheet(item: $selectedStanding) { standing in
            StudentTrackDetailView(student: student, standing: standing)
                .studentDetailSheetSizing()
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(club: project)
                .studentDetailSheetSizing()
        }
    }

    private func loadStandings() {
        guard let studentID = student.id?.uuidString else {
            finishedStandings = []
            return
        }
        finishedStandings = SequenceStandingLoader.standings(forStudentID: studentID, in: viewContext)
            .filter(\.isFinished)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(UIConstants.OpacityConstants.muted))

            Text("No Completed Sequences Yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Sequences the child has mastered every lesson of will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func finishedProjectRow(_ project: CDProject) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let book = project.bookTitle, !book.isEmpty {
                    Text(book)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .surface(
            UIConstants.CornerRadius.extraLarge,
            fill: Color.purple.opacity(UIConstants.OpacityConstants.hint),
            style: .continuous
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                .strokeBorder(Color.purple.opacity(UIConstants.OpacityConstants.accent), lineWidth: 1)
        )
    }

    private func finishedSequenceCard(standing: SequenceStanding, colorIndex: Int) -> some View {
        let accentColor = celebrationColors[colorIndex % celebrationColors.count]

        return HStack(alignment: .center, spacing: 14) {
            // Trophy/achievement icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 48, height: 48)

                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(standing.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                completedBadge(startedAt: standing.firstGivenAt)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .surface(
            UIConstants.CornerRadius.extraLarge,
            fill: LinearGradient(
                colors: [
                    accentColor.opacity(UIConstants.OpacityConstants.subtle),
                    accentColor.opacity(UIConstants.OpacityConstants.whisper)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            style: .continuous
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                .strokeBorder(accentColor.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 1)
        )
    }

    /// "Completed • Started Mar 3, 2026": when the first lesson was given, if known.
    private func completedBadge(startedAt: Date?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(AppColors.success)
            Text("Completed")
                .font(.caption)
                .foregroundStyle(AppColors.success)

            if let startedAt {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text("Started \(DateFormatters.mediumDate.string(from: startedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
