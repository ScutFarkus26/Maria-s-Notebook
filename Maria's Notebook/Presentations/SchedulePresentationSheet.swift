import SwiftUI
import SwiftData

struct SchedulePresentationSheet: View {
    let lesson: Lesson
    let onPlan: (Set<UUID>) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: Student.sortByName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [Student] {
        TestStudentsFilter.filterVisible(allStudentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var studentSearchText: String = ""
    
    private var filteredStudents: [Student] {
        let query = studentSearchText.normalizedForComparison()
        guard !query.isEmpty else { return allStudents }
        
        return allStudents.filter { student in
            student.firstName.lowercased().contains(query) ||
            student.lastName.lowercased().contains(query) ||
            student.fullName.lowercased().contains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Lesson info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan Presentation")
                        .font(.headline)
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This will add the presentation to your inbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Student selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Students")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if !selectedStudentIDs.isEmpty {
                            Text("\(selectedStudentIDs.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Search bar
                    TextField("Search students...", text: $studentSearchText)
                        .textFieldStyle(.roundedBorder)
                    
                    // Selected students
                    if !selectedStudentIDs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedStudents, id: \.id) { student in
                                    HStack(spacing: 4) {
                                        Text(StudentFormatter.displayName(for: student))
                                            .font(.caption)
                                        Button {
                                            selectedStudentIDs.remove(student.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Student list
                    List {
                        ForEach(filteredStudents, id: \.id) { student in
                            HStack {
                                Text(StudentFormatter.displayName(for: student))
                                Spacer()
                                if selectedStudentIDs.contains(student.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedStudentIDs.contains(student.id) {
                                    selectedStudentIDs.remove(student.id)
                                } else {
                                    selectedStudentIDs.insert(student.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 300)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Plan Presentation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan") {
                        onPlan(selectedStudentIDs)
                        dismiss()
                    }
                    .disabled(selectedStudentIDs.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    private var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }
}
