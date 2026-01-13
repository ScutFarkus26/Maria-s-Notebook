import SwiftUI
import SwiftData

struct StudentTrackDetailView: View {
    let enrollment: StudentTrackEnrollment
    let track: Track
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Query Presentations filtered by trackID and studentIDs
    @Query(sort: [SortDescriptor(\Presentation.presentedAt, order: .reverse)])
    private var allPresentations: [Presentation]
    
    // Query WorkModels filtered by trackID and studentID
    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]
    
    // Query Notes filtered by studentTrackEnrollment
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var allNotes: [Note]
    
    // CloudKit compatibility: Filter locally using string comparisons
    private var trackPresentations: [Presentation] {
        let trackIDString = track.id.uuidString
        let studentIDString = enrollment.studentID
        return allPresentations.filter { presentation in
            presentation.trackID == trackIDString && presentation.studentIDs.contains(studentIDString)
        }
    }
    
    private var trackWorkModels: [WorkModel] {
        let trackIDString = track.id.uuidString
        let studentIDString = enrollment.studentID
        return allWorkModels.filter { work in
            work.trackID == trackIDString && work.studentID == studentIDString
        }
    }
    
    private var trackNotes: [Note] {
        // Filter notes that have this enrollment as their studentTrackEnrollment
        return allNotes.filter { note in
            note.studentTrackEnrollment?.id == enrollment.id
        }
    }
    
    // Unified timeline items
    private struct TimelineItem: Identifiable {
        let id: UUID
        let date: Date
        let type: ItemType
        
        enum ItemType {
            case presentation(Presentation)
            case work(WorkModel)
            case note(Note)
        }
    }
    
    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []
        
        // Add presentations
        for presentation in trackPresentations {
            items.append(TimelineItem(
                id: presentation.id,
                date: presentation.presentedAt,
                type: .presentation(presentation)
            ))
        }
        
        // Add work models
        for work in trackWorkModels {
            // Use completedAt if available, otherwise createdAt
            let date = work.completedAt ?? work.createdAt
            items.append(TimelineItem(
                id: work.id,
                date: date,
                type: .work(work)
            ))
        }
        
        // Add notes
        for note in trackNotes {
            items.append(TimelineItem(
                id: note.id,
                date: note.updatedAt,
                type: .note(note)
            ))
        }
        
        // Sort by date (newest first)
        return items.sorted { $0.date > $1.date }
    }
    
    // Stats counts
    private var presentationCount: Int { trackPresentations.count }
    private var workCount: Int { trackWorkModels.count }
    private var noteCount: Int { trackNotes.count }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with stats
                    headerSection
                    
                    Divider()
                    
                    // Timeline
                    timelineSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(track.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let startedAt = enrollment.startedAt {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("Started: \(Self.dateFormatter.string(from: startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                statBadge(count: presentationCount, label: "Presentations", color: .orange)
                statBadge(count: workCount, label: "Work", color: .blue)
                statBadge(count: noteCount, label: "Observations", color: .yellow)
            }
        }
    }
    
    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timeline")
                .font(.headline)
                .foregroundStyle(.primary)
            
            if timelineItems.isEmpty {
                emptyTimelineView
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(timelineItems) { item in
                        timelineRow(item: item)
                    }
                }
            }
        }
    }
    
    private var emptyTimelineView: some View {
        ContentUnavailableView {
            Label("No Activity", systemImage: "clock")
                .foregroundStyle(.secondary)
        } description: {
            Text("No presentations, work, or observations recorded for this track yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    private func timelineRow(item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Color indicator
            Circle()
                .fill(colorForType(item.type))
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                // Date
                Text(Self.dateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Content based on type
                switch item.type {
                case .presentation(let presentation):
                    presentationRow(presentation)
                case .work(let contract):
                    workRow(contract)
                case .note(let note):
                    noteRow(note)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorForType(item.type).opacity(0.3), lineWidth: 1)
        )
    }
    
    private func presentationRow(_ presentation: Presentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Presentation")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
            
            if UUID(uuidString: presentation.lessonID) != nil {
                Text(presentation.lessonTitleSnapshot ?? "Lesson")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            } else {
                Text("Lesson")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private func workRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "briefcase.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Work")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            
            Text(work.title.isEmpty ? "Work" : work.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 4) {
                Text(work.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if work.status == .complete, work.completedAt != nil {
                    Text("• Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("Observation")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
            }
            
            Text(note.body)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }
    
    private func colorForType(_ type: TimelineItem.ItemType) -> Color {
        switch type {
        case .presentation:
            return .orange
        case .work:
            return .blue
        case .note:
            return .yellow
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let track = Track(title: "Math Fundamentals")
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(), level: .upper)
    let enrollment = StudentTrackEnrollment(
        studentID: student.id.uuidString,
        trackID: track.id.uuidString,
        startedAt: Date(),
        isActive: true
    )
    context.insert(track)
    context.insert(student)
    context.insert(enrollment)
    return StudentTrackDetailView(enrollment: enrollment, track: track)
        .previewEnvironment(using: container)
}
