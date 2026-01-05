import SwiftUI
import SwiftData

/// Unified notes section for StudentLesson that displays both new Note objects and legacy string field
struct StudentLessonNotesSectionUnified: View {
    let studentLesson: StudentLesson
    @Binding var legacyNotes: String
    let onLegacyNotesChange: (String) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note? = nil
    @State private var scopedNoteBeingEdited: ScopedNote? = nil
    
    // Get notes from relationships
    private var unifiedNotes: [Note] {
        studentLesson.noteItems ?? []
    }
    
    private var scopedNotes: [ScopedNote] {
        studentLesson.scopedNotes ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Notes")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    showAddNoteSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.accent)
                }
            }
            
            // Show new unified Note objects
            if !unifiedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unifiedNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                        unifiedNoteRow(note)
                    }
                }
            }
            
            // Show legacy ScopedNote objects
            if !scopedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scopedNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { scopedNote in
                        scopedNoteRow(scopedNote)
                    }
                }
            }
            
            // Show legacy string field (if it has content and no other notes)
            if !legacyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unifiedNotes.isEmpty && scopedNotes.isEmpty {
                TextEditor(text: Binding(
                    get: { legacyNotes },
                    set: { onLegacyNotesChange($0) }
                ))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            } else if unifiedNotes.isEmpty && scopedNotes.isEmpty && legacyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No notes yet. Tap + to add a note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(minHeight: 140)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showAddNoteSheet) {
            UnifiedNoteEditor(
                context: .studentLesson(studentLesson),
                initialNote: nil,
                onSave: { _ in
                    // Note is automatically saved via relationship
                    showAddNoteSheet = false
                },
                onCancel: {
                    showAddNoteSheet = false
                }
            )
        }
        .sheet(item: $noteBeingEdited) { note in
            UnifiedNoteEditor(
                context: .studentLesson(studentLesson),
                initialNote: note,
                onSave: { _ in
                    noteBeingEdited = nil
                },
                onCancel: {
                    noteBeingEdited = nil
                }
            )
        }
        .sheet(item: $scopedNoteBeingEdited) { scopedNote in
            LegacyNoteEditor(
                title: "Edit Note",
                text: scopedNote.body,
                onSave: { newText in
                    scopedNote.body = newText
                    try? modelContext.save()
                    scopedNoteBeingEdited = nil
                },
                onCancel: {
                    scopedNoteBeingEdited = nil
                }
            )
        }
    }
    
    @ViewBuilder
    private func unifiedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if note.category != .general {
                    Text(note.category.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                Spacer()
                Text(note.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    @ViewBuilder
    private func scopedNoteRow(_ scopedNote: ScopedNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(scopeText(for: scopedNote.scope))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.12))
                    )
                Spacer()
                Text(scopedNote.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(scopedNote.body)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contextMenu {
            Button {
                scopedNoteBeingEdited = scopedNote
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
    private func scopeText(for scope: ScopedNote.Scope) -> String {
        switch scope {
        case .all: return "All"
        case .student(_): return "Student"
        case .students(let ids): return ids.isEmpty ? "Group" : "\(ids.count) students"
        }
    }
}



