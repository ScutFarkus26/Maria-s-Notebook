import SwiftUI

struct LinkedLessonSection: View {
    let lessonsByID: [UUID: Lesson]
    let studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot]
    @Binding var selectedStudentLessonID: UUID?
    let createdDateOnlyFormatter: DateFormatter
    let onOpenLinkedDetails: () -> Void
    let onOpenBaseLesson: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "link", title: "Linked Lesson")
            
            if let selectedID = selectedStudentLessonID,
               let snapshot = studentLessonSnapshotsByID[selectedID] {
                
                let lesson = lessonsByID[snapshot.lessonID]
                let lessonName = lesson?.name ?? "Unknown Lesson"
                let date = snapshot.scheduledFor ?? snapshot.givenAt ?? snapshot.createdAt
                let formattedDate = createdDateOnlyFormatter.string(from: date)
                
                HStack(spacing: 10) {
                    Text("\(lessonName) • \(formattedDate)")
                        .font(.callout)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        onOpenLinkedDetails()
                    } label: {
                        Text("Linked Details")
                            .frame(minWidth: 0)
                    }
                    .buttonStyle(.bordered)
                    
                    if lesson != nil {
                        Button {
                            onOpenBaseLesson()
                        } label: {
                            Text("Base Lesson")
                                .frame(minWidth: 0)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Text("None")
                    .foregroundColor(.secondary)
            }
        }
    }
}
