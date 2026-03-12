import SwiftUI

struct FindStudentsSheet: View {
    let lessonID: UUID
    let existingStudentIDs: Set<UUID>
    let allStudents: [Student]
    let allLessonAssignments: [LessonAssignment]
    let onAdd: (Set<UUID>) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText: String = ""

    private var candidates: FindStudentsService.CandidateResult {
        FindStudentsService.findCandidates(
            lessonID: lessonID,
            existingStudentIDs: existingStudentIDs,
            allStudents: allStudents,
            allLessonAssignments: allLessonAssignments
        )
    }

    private func filtered(_ list: [FindStudentsService.CandidateStudent]) -> [FindStudentsService.CandidateStudent] {
        let search = searchText.normalizedForComparison()
        guard !search.isEmpty else { return list }
        return list.filter { candidate in
            let first = candidate.student.firstName.lowercased()
            let last = candidate.student.lastName.lowercased()
            let full = "\(first) \(last)"
            return first.contains(search) || last.contains(search) || full.contains(search)
        }
    }

    private var filteredNeverReceived: [FindStudentsService.CandidateStudent] {
        filtered(candidates.neverReceived)
    }

    private var filteredRedundant: [FindStudentsService.CandidateStudent] {
        filtered(candidates.redundantlyScheduled)
    }

    private var isEmpty: Bool {
        filteredNeverReceived.isEmpty && filteredRedundant.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isEmpty && searchText.isEmpty {
                    ContentUnavailableView(
                        "No Candidates",
                        systemImage: "person.2.slash",
                        description: Text("All students have already received this lesson.")
                    )
                } else {
                    List {
                        if !filteredNeverReceived.isEmpty {
                            Section("Never Received") {
                                ForEach(filteredNeverReceived) { candidate in
                                    candidateRow(candidate)
                                }
                            }
                        }

                        if !filteredRedundant.isEmpty {
                            Section("Already Received (Still Scheduled)") {
                                ForEach(filteredRedundant) { candidate in
                                    candidateRow(candidate)
                                }
                            }
                        }

                        if isEmpty && !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .searchable(text: $searchText, prompt: "Search students")
            .navigationTitle("Find Students")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIDs.count)") {
                        onAdd(selectedIDs)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func candidateRow(_ candidate: FindStudentsService.CandidateStudent) -> some View {
        Button {
            adaptiveWithAnimation {
                if selectedIDs.contains(candidate.id) {
                    selectedIDs.remove(candidate.id)
                } else {
                    selectedIDs.insert(candidate.id)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StudentFormatter.displayName(for: candidate.student))
                        .foregroundStyle(.primary)
                    Text(candidate.ageString)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedIDs.contains(candidate.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
