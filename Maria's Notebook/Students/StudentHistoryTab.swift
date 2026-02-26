// StudentHistoryTab.swift
// History tab showing student's finished track enrollments

import SwiftUI
import SwiftData

struct StudentHistoryTab: View {
    let student: Student

    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]

    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]

    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)])
    private var allProjects: [Project]

    @State private var selectedEnrollment: StudentTrackEnrollment?
    @State private var selectedProject: Project?

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var tracksByID: [String: Track] {
        Dictionary(allTracks.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Deduplicated finished enrollments - keeps only one enrollment per track TITLE (not ID)
    /// This handles the case where duplicate Track objects exist with the same title
    private var finishedEnrollments: [StudentTrackEnrollment] {
        let sid = student.id.uuidString
        let finished = allEnrollments.filter { $0.studentID == sid && !$0.isActive }

        // Deduplicate by track title, keeping the one with more activity
        var bestByTitle: [String: StudentTrackEnrollment] = [:]
        for enrollment in finished {
            guard let track = tracksByID[enrollment.trackID] else { continue }
            let title = track.title

            if let existing = bestByTitle[title] {
                // Keep the newer one (first in sorted array since sorted by createdAt desc)
                if enrollment.createdAt > existing.createdAt {
                    bestByTitle[title] = enrollment
                }
            } else {
                bestByTitle[title] = enrollment
            }
        }
        return Array(bestByTitle.values).sorted { ($0.createdAt) > ($1.createdAt) }
    }

    private var finishedProjects: [Project] {
        let sid = student.id.uuidString
        return allProjects.filter { $0.memberStudentIDs.contains(sid) && !$0.isActive }
    }

    // Celebration colors for completed tracks
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

                // Finished Tracks Section
                if finishedEnrollments.isEmpty {
                    if finishedProjects.isEmpty {
                        emptyStateView
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text("Completed Tracks")
                                .font(.headline)
                        }
                        .padding(.horizontal, 4)

                        ForEach(Array(finishedEnrollments.enumerated()), id: \.element.id) { index, enrollment in
                            if let track = tracksByID[enrollment.trackID] {
                                finishedTrackCard(enrollment: enrollment, track: track, colorIndex: index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedEnrollment = enrollment
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(club: project)
                .studentDetailSheetSizing()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("No Completed Tracks Yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Completed tracks will appear here as achievements!")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func finishedProjectRow(_ project: Project) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.purple.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }

    private func finishedTrackCard(enrollment: StudentTrackEnrollment, track: Track, colorIndex: Int) -> some View {
        let accentColor = celebrationColors[colorIndex % celebrationColors.count]

        return HStack(alignment: .center, spacing: 14) {
            // Trophy/achievement icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if let startedAt = enrollment.startedAt {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(Self.dateFormatter.string(from: startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.08), accentColor.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}
