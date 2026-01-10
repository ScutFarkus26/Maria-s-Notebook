import SwiftUI
import SwiftData

struct StudentTracksTab: View {
    let student: Student
    
    @Environment(\.modelContext) private var modelContext
    
    // Query all StudentTrackEnrollment objects; we'll filter by studentID
    @Query(sort: [SortDescriptor(\StudentTrackEnrollment.createdAt, order: .reverse)])
    private var allEnrollments: [StudentTrackEnrollment]
    
    // Query all Tracks for lookup
    @Query(sort: [SortDescriptor(\Track.title)])
    private var allTracks: [Track]
    
    @State private var selectedEnrollment: StudentTrackEnrollment? = nil
    
    // CloudKit compatibility: Convert UUID to String for comparison
    private var enrollmentsForStudent: [StudentTrackEnrollment] {
        let studentIDString = student.id.uuidString
        return allEnrollments.filter { $0.studentID == studentIDString }
    }
    
    private var tracksByID: [String: Track] {
        Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id.uuidString, $0) })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if enrollmentsForStudent.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(enrollmentsForStudent) { enrollment in
                        if let track = tracksByID[enrollment.trackID] {
                            enrollmentRow(enrollment: enrollment, track: track)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEnrollment = enrollment
                                }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selectedEnrollment) { enrollment in
            if let track = tracksByID[enrollment.trackID] {
                StudentTrackDetailView(enrollment: enrollment, track: track)
                    .studentDetailSheetSizing()
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Track Enrollments", systemImage: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
        } description: {
            Text("This student is not enrolled in any tracks yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func enrollmentRow(enrollment: StudentTrackEnrollment, track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if enrollment.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Inactive", systemImage: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let startedAt = enrollment.startedAt {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.dateFormatter.string(from: startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let notes = enrollment.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
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
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentTracksTab(student: student)
        .previewEnvironment(using: container)
        .padding()
}
