// StudentTracksTab.swift
// Track enrollments tab showing individual tracks with stats and activity

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StudentTracksTab: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Inputs
    let student: Student
    
    // MARK: - State
    @State private var selectedEnrollment: StudentTrackEnrollment? = nil
    
    // MARK: - Queries
    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]
    
    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]
    
    @Query(sort: [SortDescriptor(\Presentation.presentedAt, order: .reverse)])
    private var allPresentations: [Presentation]
    
    @Query(sort: [SortDescriptor(\WorkContract.createdAt, order: .reverse)])
    private var allWorkContracts: [WorkContract]
    
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var allNotes: [Note]
    
    // MARK: - Computed Properties
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
    
    // MARK: - Computed Data
    private var enrollmentsForStudent: [StudentTrackEnrollment] {
        let studentIDString = student.id.uuidString
        return allEnrollments.filter { $0.studentID == studentIDString }
    }
    
    private var tracksByID: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id.uuidString, $0) })
    }
    
    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if enrollmentsForStudent.isEmpty {
                    emptyStateView
                        .padding(.top, 60)
                } else {
                    ForEach(enrollmentsForStudent) { enrollment in
                        if let track = tracksByID[enrollment.trackID] {
                            enrollmentCard(
                                enrollment: enrollment,
                                track: track
                            )
                            .padding(.horizontal, 4)
                            .onTapGesture {
                                selectedEnrollment = enrollment
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Track Enrollments", systemImage: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
        } description: {
            Text("This student is not enrolled in any tracks yet.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Enrollment Card
    @ViewBuilder
    private func enrollmentCard(
        enrollment: StudentTrackEnrollment,
        track: Track
    ) -> some View {
        let studentIDString = student.id.uuidString
        let trackIDString = track.id.uuidString
        
        // Get stats for this track enrollment
        let presentations = allPresentations.filter {
            $0.trackID == trackIDString && $0.studentIDs.contains(studentIDString)
        }
        let workContracts = allWorkContracts.filter {
            $0.trackID == trackIDString && $0.studentID == studentIDString
        }
        let notes = allNotes.filter {
            $0.studentTrackEnrollment?.id == enrollment.id
        }
        
        let presentationCount = presentations.count
        let workCount = workContracts.count
        let noteCount = notes.count
        let totalActivity = presentationCount + workCount + noteCount
        
        // Get last activity date
        let lastActivityDate: Date? = {
            var dates: [Date] = []
            dates.append(contentsOf: presentations.map { $0.presentedAt })
            dates.append(contentsOf: workContracts.compactMap { $0.completedAt ?? $0.createdAt })
            dates.append(contentsOf: notes.map { $0.updatedAt })
            return dates.max()
        }()
        
        let trackColor = trackColorForTitle(track.title)
        let hasNotes = enrollment.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        
        VStack(alignment: .leading, spacing: 16) {
            // Header with track icon and title
            HStack(spacing: 12) {
                // Track icon/indicator
                ZStack {
                    Circle()
                        .fill(trackColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(trackColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    // Started date or enrollment date
                    if let startedAt = enrollment.startedAt {
                        Text("Started \(startedAt, style: .relative)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Enrolled \(enrollment.createdAt, style: .relative)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Active/Inactive status badge
                if enrollment.isActive {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Stats section
            if totalActivity > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(totalActivity)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(trackColor)
                        
                        Text("total activities")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    
                    // Stats badges
                    HStack(spacing: 12) {
                        statBadge(
                            count: presentationCount,
                            label: "Presentations",
                            icon: "presentation",
                            color: .orange
                        )
                        statBadge(
                            count: workCount,
                            label: "Work",
                            icon: "briefcase.fill",
                            color: .blue
                        )
                        statBadge(
                            count: noteCount,
                            label: "Notes",
                            icon: "note.text",
                            color: .yellow
                        )
                    }
                    
                    // Last activity
                    if let lastActivityDate = lastActivityDate {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            
                            Text("Last activity \(lastActivityDate, style: .relative)")
                                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                // No activity yet
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    Text("No activity recorded yet")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
            
            // Enrollment notes preview
            if hasNotes, let notes = enrollment.notes {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundStyle(trackColor.opacity(0.7))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text(notes)
                            .font(.system(size: AppTheme.FontSize.callout, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(trackColor.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            trackColor.opacity(enrollment.isActive ? 0.3 : 0.15),
                            trackColor.opacity(enrollment.isActive ? 0.15 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: enrollment.isActive ? 2 : 1
                )
        )
    }
    
    // MARK: - Stat Badge
    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Track Color Helper
    private func trackColorForTitle(_ title: String) -> Color {
        // Generate a consistent color based on the track title
        // This provides visual variety while being deterministic
        let hash = title.hash
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .mint, .teal, .cyan, .indigo
        ]
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentTracksTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
