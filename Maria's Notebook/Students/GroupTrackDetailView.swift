// GroupTrackDetailView.swift
// Detail view for a group-based track showing lessons in order

import SwiftUI
import SwiftData

struct GroupTrackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    let subject: String
    let group: String
    
    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.orderInGroup)])
    private var allLessons: [Lesson]
    
    private var groupTrack: GroupTrack? {
        try? GroupTrackService.getGroupTrack(subject: subject, group: group, modelContext: modelContext)
    }
    
    private var effectiveTrackSettings: (isSequential: Bool, isExplicitlyDisabled: Bool) {
        (try? GroupTrackService.getEffectiveTrackSettings(subject: subject, group: group, modelContext: modelContext)) ?? (isSequential: true, isExplicitlyDisabled: false)
    }
    
    private var lessons: [Lesson] {
        // Check if this group is a track (all groups are tracks by default unless explicitly disabled)
        guard GroupTrackService.isTrack(subject: subject, group: group, modelContext: modelContext) else {
            return []
        }
        
        // If we have an actual GroupTrack record, use it
        if let track = groupTrack {
            return GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)
        }
        
        // No record exists = default behavior = sequential track
        // Filter and sort lessons for this group manually
        let settings = effectiveTrackSettings
        let filtered = allLessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject.trimmed()) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group.trimmed()) == .orderedSame
        }
        
        return filtered.sorted { lhs, rhs in
            if settings.isSequential {
                // Sequential: respect orderInGroup
                if lhs.orderInGroup != rhs.orderInGroup {
                    return lhs.orderInGroup < rhs.orderInGroup
                }
            }
            // Fallback to name for stable ordering
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    var body: some View {
        Form {
            Section("Track") {
                HStack {
                    Text("Subject:")
                    Spacer()
                    Text(subject)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Group:")
                    Spacer()
                    Text(group)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Type:")
                    Spacer()
                    let settings = effectiveTrackSettings
                    Label(
                        settings.isSequential ? "Sequential" : "Unordered",
                        systemImage: settings.isSequential ? "list.number" : "list.bullet"
                    )
                    .foregroundColor(.secondary)
                }
            }
            
            Section("Lessons") {
                if lessons.isEmpty {
                    Text("No lessons in this group.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonStepRow(
                            lesson: lesson,
                            stepNumber: effectiveTrackSettings.isSequential ? index + 1 : nil
                        )
                    }
                }
            }
        }
        .navigationTitle("\(subject) · \(group)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct LessonStepRow: View {
    let lesson: Lesson
    let stepNumber: Int?
    
    var body: some View {
        HStack {
            if let stepNumber = stepNumber {
                Text("\(stepNumber).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.body)
                
                if !lesson.subheading.isEmpty {
                    Text(lesson.subheading)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
