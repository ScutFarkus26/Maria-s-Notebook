import SwiftUI

struct LinkedLessonSection: View {
    let lessonsByID: [UUID: Lesson]
    let studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot]
    @Binding var selectedStudentLessonID: UUID?
    let createdDateOnlyFormatter: DateFormatter
    let onOpenLinkedDetails: () -> Void
    let onOpenBaseLesson: () -> Void
    let selectedStudentIDs: Set<UUID>
    let onCreateNewStudentLesson: () -> Void
    @State private var showingLinkPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "link", title: "Linked Lesson")
                .contentShape(Rectangle())
                .onTapGesture { showingLinkPicker = true }
            
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
                HStack(spacing: 10) {
                    Text("None")
                        .foregroundColor(.secondary)
                        .onTapGesture { showingLinkPicker = true }
                    Spacer()
                    Button {
                        showingLinkPicker = true
                    } label: {
                        Label("Link Lesson…", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showingLinkPicker) {
            NavigationStack {
                List {
                    let sorted = studentLessonSnapshotsByID.values.sorted { lhs, rhs in
                        let ld = lhs.scheduledFor ?? lhs.givenAt ?? lhs.createdAt
                        let rd = rhs.scheduledFor ?? rhs.givenAt ?? rhs.createdAt
                        return ld > rd
                    }
                    let filtered = sorted.filter { Set($0.studentIDs).isSuperset(of: selectedStudentIDs) }
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            "No matching lessons",
                            systemImage: "magnifyingglass",
                            description: Text("No student lessons include all selected students.")
                        )
                    } else {
                        ForEach(filtered, id: \.id) { snap in
                            let lesson = lessonsByID[snap.lessonID]
                            let name = lesson?.name ?? "Lesson"
                            let date = createdDateOnlyFormatter.string(from: snap.scheduledFor ?? snap.givenAt ?? snap.createdAt)
                            Button {
                                selectedStudentLessonID = snap.id
                                showingLinkPicker = false
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text(date).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            showingLinkPicker = false
                            onCreateNewStudentLesson()
                        } label: {
                            Label("Create New Student Lesson…", systemImage: "plus")
                        }
                    }
                }
                .navigationTitle("Link to Lesson")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingLinkPicker = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 520)
            #endif
        }
    }
}

