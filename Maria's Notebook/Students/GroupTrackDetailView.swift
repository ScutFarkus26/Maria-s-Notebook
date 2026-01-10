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
    
    private var lessons: [Lesson] {
        guard let track = groupTrack else { return [] }
        return GroupTrackService.getLessonsForTrack(track: track, allLessons: allLessons)
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
                    if let track = groupTrack {
                        Label(
                            track.isSequential ? "Sequential" : "Unordered",
                            systemImage: track.isSequential ? "list.number" : "list.bullet"
                        )
                        .foregroundColor(.secondary)
                    }
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
                            stepNumber: groupTrack?.isSequential == true ? index + 1 : nil
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
