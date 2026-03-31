// StudentHistoryTab.swift
// History tab showing student's finished track enrollments

import SwiftUI
import CoreData

struct StudentHistoryTab: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentTrackEnrollmentEntity.createdAt, ascending: false)])
    private var allEnrollments: FetchedResults<CDStudentTrackEnrollmentEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDTrackEntity.title, ascending: true)])
    private var allTracks: FetchedResults<CDTrackEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDProject.createdAt, ascending: false)])
    private var allProjects: FetchedResults<CDProject>

    @State private var selectedEnrollment: CDStudentTrackEnrollmentEntity?
    @State private var selectedProject: CDProject?

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var tracksByID: [String: CDTrackEntity] {
        Dictionary(allTracks.compactMap { t in t.id.map { ($0.uuidString, t) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Deduplicated finished enrollments - keeps only one enrollment per track TITLE (not ID)
    /// This handles the case where duplicate CDTrackEntity objects exist with the same title
    private var finishedEnrollments: [CDStudentTrackEnrollmentEntity] {
        let sid = student.id?.uuidString ?? ""
        let finished = allEnrollments.filter { $0.studentID == sid && !$0.isActive }

        // Deduplicate by track title, keeping the one with more activity
        var bestByTitle: [String: CDStudentTrackEnrollmentEntity] = [:]
        for enrollment in finished {
            guard let track = tracksByID[enrollment.trackID] else { continue }
            let title = track.title

            if let existing = bestByTitle[title] {
                // Keep the newer one (first in sorted array since sorted by createdAt desc)
                if (enrollment.createdAt ?? .distantPast) > (existing.createdAt ?? .distantPast) {
                    bestByTitle[title] = enrollment
                }
            } else {
                bestByTitle[title] = enrollment
            }
        }
        return Array(bestByTitle.values).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var finishedProjects: [CDProject] {
        let sid = student.id?.uuidString ?? ""
        return allProjects.filter { $0.memberStudentIDsArray.contains(sid) && !$0.isActive }
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

                        ForEach(Array(finishedEnrollments.enumerated()), id: \.element.objectID) { index, enrollment in
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
                .foregroundStyle(.secondary.opacity(UIConstants.OpacityConstants.muted))

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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.purple.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.purple.opacity(UIConstants.OpacityConstants.accent), lineWidth: 1)
        )
    }

    private func finishedTrackCard(enrollment: CDStudentTrackEnrollmentEntity, track: CDTrackEntity, colorIndex: Int) -> some View {
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
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)

                    if let startedAt = enrollment.startedAt {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(DateFormatters.mediumDate.string(from: startedAt))
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
                        colors: [accentColor.opacity(UIConstants.OpacityConstants.subtle), accentColor.opacity(UIConstants.OpacityConstants.whisper)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accentColor.opacity(UIConstants.OpacityConstants.moderate), lineWidth: 1)
        )
    }

}
