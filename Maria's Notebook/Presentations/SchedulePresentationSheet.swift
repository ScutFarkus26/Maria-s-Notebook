import SwiftUI
import CoreData

struct SchedulePresentationSheet: View {
    let lesson: CDLesson
    let onPlan: (Set<UUID>) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true), NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID.filter(\.isEnrolled), show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var studentSearchText: String = ""
    
    private var filteredStudents: [CDStudent] {
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
                // CDLesson info
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
                
                // CDStudent selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Students")
                            .font(.subheadline.weight(.bold))
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
                                            if let studentID = student.id {
                                                selectedStudentIDs.remove(studentID)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent)))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // CDStudent list
                    List {
                        ForEach(filteredStudents, id: \.id) { student in
                            HStack {
                                Text(StudentFormatter.displayName(for: student))
                                Spacer()
                                if let studentID = student.id, selectedStudentIDs.contains(studentID) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard let studentID = student.id else { return }
                                if selectedStudentIDs.contains(studentID) {
                                    selectedStudentIDs.remove(studentID)
                                } else {
                                    selectedStudentIDs.insert(studentID)
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
            .inlineNavigationTitle()
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
    
    private var selectedStudents: [CDStudent] {
        allStudents.filter { student in
            guard let studentID = student.id else { return false }
            return selectedStudentIDs.contains(studentID)
        }
    }
}
