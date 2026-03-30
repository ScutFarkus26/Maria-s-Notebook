import SwiftUI
import SwiftData

enum TrackFilterType: String {
    case presentations
    case work
    case notes
}

// swiftlint:disable:next type_body_length
struct TrackFilteredListView: View, Identifiable {
    let enrollment: StudentTrackEnrollment
    let track: Track
    let filterType: TrackFilterType
    let allLessonAssignments: [LessonAssignment]
    let allWorkModels: [WorkModel]
    let allNotes: [Note]
    let allLessons: [Lesson]
    let onDismiss: () -> Void

    var id: String {
        "\(filterType.rawValue)_\(enrollment.id.uuidString)"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(allLessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Filter LessonAssignments (unified model) by track and student
    private var filteredLessonAssignments: [LessonAssignment] {
        let trackIDString = track.id.uuidString
        let studentIDString = enrollment.studentID
        return allLessonAssignments.filter { assignment in
            assignment.trackID == trackIDString &&
            assignment.studentIDs.contains(studentIDString) &&
            assignment.state == .presented
        }
    }
    
    private var filteredWorkModels: [WorkModel] {
        let trackIDString = track.id.uuidString
        let studentIDString = enrollment.studentID
        return allWorkModels.filter { work in
            work.trackID == trackIDString && work.studentID == studentIDString
        }
    }
    
    private var filteredNotes: [Note] {
        return allNotes.filter { note in
            note.studentTrackEnrollment?.id == enrollment.id
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch filterType {
                    case .presentations:
                        presentationsList
                    case .work:
                        workList
                    case .notes:
                        notesList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var title: String {
        switch filterType {
        case .presentations:
            return "Presentations - \(track.title)"
        case .work:
            return "Work - \(track.title)"
        case .notes:
            return "Observations - \(track.title)"
        }
    }
    
    private var presentationsList: some View {
        Group {
            if filteredLessonAssignments.isEmpty {
                ContentUnavailableView {
                    Label("No Presentations", systemImage: "person.3")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("No presentations found for this track.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Show LessonAssignments (unified model)
                    ForEach(filteredLessonAssignments) { assignment in
                        lessonAssignmentRow(assignment)
                    }
                }
            }
        }
    }
    
    private var workList: some View {
        Group {
            if filteredWorkModels.isEmpty {
                ContentUnavailableView {
                    Label("No Work", systemImage: "briefcase")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("No work found for this track.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredWorkModels) { work in
                        workRow(work)
                    }
                }
            }
        }
    }
    
    private var notesList: some View {
        Group {
            if filteredNotes.isEmpty {
                ContentUnavailableView {
                    Label("No Observations", systemImage: "note.text")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("No observations found for this track.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredNotes) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }
    
    private func lessonAssignmentRow(_ assignment: LessonAssignment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(AppColors.warning)
                    .font(.caption)

                Text("Presentation")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.warning)

                Spacer()

                if let presentedAt = assignment.presentedAt {
                    Text(DateFormatters.mediumDate.string(from: presentedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lessonID = UUID(uuidString: assignment.lessonID),
               let lesson = lessonsByID[lessonID] {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.body)
                    .foregroundStyle(.primary)
            } else if let titleSnapshot = assignment.lessonTitleSnapshot, !titleSnapshot.isEmpty {
                Text(titleSnapshot)
                    .font(.body)
                    .foregroundStyle(.primary)
            } else {
                Text("Lesson")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func workRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                
                Text("Work")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                
                Spacer()
                
                Text(DateFormatters.mediumDate.string(from: work.completedAt ?? work.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(work.title.isEmpty ? "Work" : work.title)
                .font(.body)
                .foregroundStyle(.primary)
            
            HStack(spacing: 8) {
                Text(work.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                
                Text("Observation")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                
                Spacer()
                
                Text(DateFormatters.mediumDate.string(from: note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(nil)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.yellow.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
    
}
