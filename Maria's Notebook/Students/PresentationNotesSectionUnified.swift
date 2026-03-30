import SwiftUI
import SwiftData

/// Unified notes section for a LessonAssignment that displays both new Note objects and legacy string field
struct PresentationNotesSectionUnified: View {
    let lessonAssignment: LessonAssignment
    @Binding var legacyNotes: String
    let onLegacyNotesChange: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showAddNoteSheet: Bool = false
    @State private var noteBeingEdited: Note?

    // We already have the LessonAssignment directly — no matching needed
    private var matchedLessonAssignments: [LessonAssignment] {
        [lessonAssignment]
    }

    private var matchedAssignmentIDs: Set<UUID> {
        Set([lessonAssignment.id])
    }

    // Get notes from WorkModels associated with this lesson assignment
    private var workNotesForThisPresentation: [Note] {
        do {
            // Fetch all Notes to avoid SwiftData predicate limitations
            let allNotes = try modelContext.fetch(FetchDescriptor<Note>())

            // Convert studentIDs (String array) to UUID set for comparison
            let presentationStudentIDs = Set(lessonAssignment.studentIDs.compactMap { UUID(uuidString: $0) })
            let presentationLessonID = lessonAssignment.lessonID

            return allNotes.filter { note in
                // Must have a work relationship
                guard let work = note.work else { return false }

                // Work's lessonID must match lessonAssignment's lessonID
                guard work.lessonID == presentationLessonID else { return false }

                // Filter by scope to ensure note is relevant to this group
                switch note.scope {
                case .all:
                    return true
                case .student(let id):
                    return presentationStudentIDs.contains(id)
                case .students(let ids):
                    return ids.contains { presentationStudentIDs.contains($0) }
                }
            }
        } catch {
            return []
        }
    }

    // Get lesson-attached notes from the LessonAssignment
    private var lessonNotes: [Note] {
        lessonAssignment.unifiedNotes ?? []
    }
    
    // Get all unified notes (lesson + work),
    // merged, de-duplicated, and sorted
    private var allUnifiedNotes: [Note] {
        let lessonNotes = self.lessonNotes
        let workNotes = workNotesForThisPresentation

        // Merge and de-duplicate by note.id (keep first occurrence)
        var seenIDs: Set<UUID> = []
        var merged: [Note] = []

        for note in lessonNotes + workNotes where !seenIDs.contains(note.id) {
            seenIDs.insert(note.id)
            merged.append(note)
        }
        
        // Sort by createdAt descending
        return merged.sorted { $0.createdAt > $1.createdAt }
    }
    
    // Legacy computed property for backwards compatibility (now just uses allUnifiedNotes)
    private var unifiedNotes: [Note] {
        allUnifiedNotes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text("Notes")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    showAddNoteSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.accent)
                }
            }
            // Show Note objects
            if !allUnifiedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allUnifiedNotes, id: \.id) { note in
                        unifiedNoteRow(note)
                    }
                }
            }

            // Show legacy string field (if it has content and no other notes)
            if !legacyNotes.trimmed().isEmpty && allUnifiedNotes.isEmpty {
                TextEditor(text: Binding(
                    get: { legacyNotes },
                    set: { onLegacyNotesChange($0) }
                ))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium), lineWidth: 1)
                )
            } else if allUnifiedNotes.isEmpty && legacyNotes.trimmed().isEmpty {
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
                context: .presentation(lessonAssignment),
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
                context: .presentation(lessonAssignment),
                initialNote: note,
                onSave: { _ in
                    noteBeingEdited = nil
                },
                onCancel: {
                    noteBeingEdited = nil
                }
            )
        }
    }
    
    @ViewBuilder
    private func unifiedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(note.tags, id: \.self) { tag in
                    TagBadge(tag: tag, compact: true)
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        )
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: "pencil")
            }
        }
    }
    
}
