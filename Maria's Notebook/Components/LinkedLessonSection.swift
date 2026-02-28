import SwiftUI

struct LinkedLessonSection: View {
    let lessonsByID: [UUID: Lesson]
    let presentationSnapshotsByID: [UUID: LessonAssignmentSnapshot]
    @Binding var selectedPresentationID: UUID?
    let createdDateOnlyFormatter: DateFormatter
    let onOpenLinkedDetails: () -> Void
    let onOpenBaseLesson: () -> Void
    let selectedStudentIDs: Set<UUID>
    let onCreateNewPresentation: () -> Void
    @State private var showingLinkPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "link", title: "Linked Lesson")
                .contentShape(Rectangle())
                .onTapGesture { showingLinkPicker = true }
            
            if let selectedID = selectedPresentationID,
               let snapshot = presentationSnapshotsByID[selectedID] {
                
                let lesson = lessonsByID[snapshot.lessonID]
                let lessonName = lesson?.name ?? "Unknown Lesson"
                let date = snapshot.scheduledFor ?? snapshot.presentedAt ?? snapshot.createdAt
                let formattedDate = createdDateOnlyFormatter.string(from: date)
                
                HStack(spacing: 10) {
                    Text("\(lessonName) • \(formattedDate)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                    
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
                        .foregroundStyle(.secondary)
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
                    let sorted = presentationSnapshotsByID.values.sorted(by: { (lhs: LessonAssignmentSnapshot, rhs: LessonAssignmentSnapshot) in
                        let ld = lhs.scheduledFor ?? lhs.presentedAt ?? lhs.createdAt
                        let rd = rhs.scheduledFor ?? rhs.presentedAt ?? rhs.createdAt
                        return ld > rd
                    })
                    let filtered = sorted.filter { Set($0.studentIDs).isSuperset(of: selectedStudentIDs) }
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            "No matching lessons",
                            systemImage: "magnifyingglass",
                            description: Text("No presentations include all selected students.")
                        )
                    } else {
                        ForEach(filtered, id: \.id) { snap in
                            let lesson = lessonsByID[snap.lessonID]
                            let name = lesson?.name ?? "Lesson"
                            let date = createdDateOnlyFormatter.string(from: snap.scheduledFor ?? snap.presentedAt ?? snap.createdAt)
                            Button {
                                selectedPresentationID = snap.id
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
                            onCreateNewPresentation()
                        } label: {
                            Label("Create New Presentation…", systemImage: "plus")
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

