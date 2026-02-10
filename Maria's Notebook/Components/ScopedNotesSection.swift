import SwiftUI
import Foundation

struct ScopedNotesSection: View {
    let title: String
    let notes: [Note]
    let availableStudents: [Student]
    let defaultScope: NoteScope
    let onAddNote: (String, NoteScope) -> Void

    @State private var draftBody: String = ""
    @State private var scopeChoice: ScopeChoice

    internal enum ScopeChoice: Hashable {
        case all
        case student(UUID)
    }

    init(
        title: String,
        notes: [Note],
        availableStudents: [Student],
        defaultScope: NoteScope = .all,
        onAddNote: @escaping (String, NoteScope) -> Void
    ) {
        self.title = title
        self.notes = notes
        self.availableStudents = availableStudents
        self.defaultScope = defaultScope
        self.onAddNote = onAddNote

        switch defaultScope {
        case .all:
            _scopeChoice = State(initialValue: .all)
        case let .student(id):
            _scopeChoice = State(initialValue: .student(id))
        case .students:
            // The defaultScope enum is defined as .all, .student, .students but instructions only mention .all and .student tags,
            // So treat .students as .all for init here for safety as we have no tag for multiple students.
            _scopeChoice = State(initialValue: .all)
        }
    }

    private var sortedNotes: [Note] {
        notes.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.createdAt > $1.createdAt
        }
    }
    
    private var studentsByID: [UUID: Student] {
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        Dictionary(availableStudents.uniqueByID.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func scopeLabel(for note: Note) -> String {
        switch note.scope {
        case .all:
            return "All"
        case let .student(id):
            if let student = studentsByID[id] {
                return displayName(for: student)
            } else {
                return "Student"
            }
        case let .students(ids):
            return "\(ids.count) students"
        }
    }

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        return student.fullName.trimmed()
    }

    private var scopeFromChoice: NoteScope {
        switch scopeChoice {
        case .all:
            return .all
        case let .student(id):
            return .student(id)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                Text(title)
                    .font(.headline)
                Spacer()
            }

            if sortedNotes.isEmpty {
                Text("No notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedNotes, id: \.id) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                Text(scopeLabel(for: note))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .strokeBorder(Color.secondary, lineWidth: 1)
                                    )
                                HStack(spacing: 0) {
                                    Text(note.updatedAt, style: .date)
                                    Text(" ")
                                    Text(note.updatedAt, style: .time)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 8) {
                TextField("Add a note…", text: $draftBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                HStack {
                    Picker("Scope", selection: $scopeChoice) {
                        Text("All").tag(ScopeChoice.all)
                        ForEach(availableStudents.sorted(by: StudentSortComparator.byFirstName), id: \.id) { student in
                            Text(displayName(for: student))
                                .tag(ScopeChoice.student(student.id))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    Spacer()

                    Button {
                        let trimmedDraft = draftBody.trimmed()
                        guard !trimmedDraft.isEmpty else { return }
                        onAddNote(trimmedDraft, scopeFromChoice)
                        draftBody = ""
                    } label: {
                        Text("Add")
                    }
                    .disabled(draftBody.trimmed().isEmpty)
                }
            }
        }
        .padding()
    }
}

#if DEBUG
import SwiftUI

struct ScopedNotesSection_Previews: PreviewProvider {
    static var previews: some View {
        ScopedNotesSection(
            title: "Notes",
            notes: [],
            availableStudents: [],
            defaultScope: .all,
            onAddNote: { _, _ in }
        )
        .frame(width: 350)
        .padding()
    }
}
#endif
