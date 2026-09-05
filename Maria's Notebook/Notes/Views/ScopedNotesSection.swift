import SwiftUI
import Foundation
import CoreData

struct ScopedNotesSection: View {
    let title: String
    let notes: [CDNote]
    let availableStudents: [CDStudent]
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
        notes: [CDNote],
        availableStudents: [CDStudent],
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
            scopeChoice = .all
        case let .student(id):
            scopeChoice = .student(id)
        case .students:
            // The defaultScope enum is defined as .all, .student, .students but
            // instructions only mention .all and .student tags,
            // So treat .students as .all for init here for safety as we have no tag for multiple students.
            scopeChoice = .all
        }
    }

    private var sortedNotes: [CDNote] {
        notes.sorted {
            let u0 = $0.updatedAt ?? .distantPast
            let u1 = $1.updatedAt ?? .distantPast
            if u0 != u1 {
                return u0 > u1
            }
            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }
    
    private var studentsByID: [UUID: CDStudent] {
        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        Dictionary(
            availableStudents.uniqueByID.compactMap { student in
                guard let id = student.id else { return nil }
                return (id, student)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func scopeLabel(for note: CDNote) -> String {
        switch note.scope {
        case .all:
            return "All"
        case let .student(id):
            if let student = studentsByID[id] {
                return StudentFormatter.displayName(for: student)
            } else {
                return "Student"
            }
        case let .students(ids):
            return "\(ids.count) students"
        }
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
                    ForEach(sortedNotes, id: \.objectID) { note in
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
                                    Text(note.updatedAt ?? Date(), style: .date)
                                    Text(" ")
                                    Text(note.updatedAt ?? Date(), style: .time)
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
                        ForEach(
                            availableStudents.sorted(by: StudentSortComparator.byFirstName),
                            id: \.objectID
                        ) { student in
                            if let studentID = student.id {
                                Text(StudentFormatter.displayName(for: student))
                                    .tag(ScopeChoice.student(studentID))
                            }
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
// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ScopedNotesSectionPreview: View {
    var body: some View {
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

#Preview {
    ScopedNotesSectionPreview()
}
#endif
