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
    
    // Helper computed values for matching
    private var slID: String {
        studentLesson.id.uuidString
    }
    
    private var slLessonID: String {
        studentLesson.resolvedLessonID.uuidString
    }
    
    private var slStudentIDs: Set<String> {
        Set(studentLesson.resolvedStudentIDs.map { $0.uuidString })
    }
    
    private var slGivenDay: Date? {
        studentLesson.givenAt.map { Calendar.current.startOfDay(for: $0) }
    }
    
    // Matched LessonAssignments using robust matching with migratedFromStudentLessonID as primary
    private var matchedLessonAssignments: [LessonAssignment] {
        do {
            let allAssignments = try modelContext.fetch(FetchDescriptor<LessonAssignment>())

            var matched: [LessonAssignment] = []
            var seenIDs: Set<UUID> = []

            // Primary match: migratedFromStudentLessonID == studentLesson.id.uuidString
            for la in allAssignments {
                if let legacyID = la.migratedFromStudentLessonID,
                   legacyID == slID,
                   !seenIDs.contains(la.id) {
                    matched.append(la)
                    seenIDs.insert(la.id)
                }
            }

            // Fallback: lessonID matches AND student set intersection/subset
            if matched.isEmpty {
                var candidates: [LessonAssignment] = []

                for la in allAssignments {
                    if seenIDs.contains(la.id) { continue }

                    // Check lessonID match
                    let lessonMatch = la.lessonID == slLessonID || la.lessonID == studentLesson.lessonID
                    guard lessonMatch else { continue }

                    // Check student match
                    let laStudentIDs = Set(la.studentIDs)
                    let studentMatch = laStudentIDs == slStudentIDs ||
                                     laStudentIDs.isSubset(of: slStudentIDs) ||
                                     !laStudentIDs.intersection(slStudentIDs).isEmpty
                    guard studentMatch else { continue }

                    candidates.append(la)
                }

                // If multiple candidates, choose by time proximity
                if candidates.count == 1 {
                    matched.append(candidates[0])
                } else if candidates.count > 1 {
                    var bestMatch: LessonAssignment?
                    var minTimeDifference: TimeInterval = .greatestFiniteMagnitude

                    let slDate: Date
                    if let givenAt = studentLesson.givenAt {
                        slDate = givenAt
                    } else if let scheduledFor = studentLesson.scheduledFor {
                        slDate = scheduledFor
                    } else {
                        slDate = studentLesson.createdAt
                    }

                    for candidate in candidates {
                        if let presentedAt = candidate.presentedAt {
                            let timeDifference = abs(presentedAt.timeIntervalSince(slDate))
                            if timeDifference < minTimeDifference {
                                minTimeDifference = timeDifference
                                bestMatch = candidate
                            }
                        }
                    }

                    if let best = bestMatch {
                        matched.append(best)
                    } else {
                        matched.append(candidates[0])
                    }
                }
            }

            return matched
        } catch {
            return []
        }
    }
    
    // Get matched assignment IDs for efficient note fetching
    private var matchedAssignmentIDs: Set<UUID> {
        Set(matchedLessonAssignments.map { $0.id })
    }

    // Get notes from matched LessonAssignments
    private var presentationNotesForThisLesson: [Note] {
        let matchedIDs = matchedAssignmentIDs
        guard !matchedIDs.isEmpty else { return [] }

        do {
            // Try to use relationship arrays first (more efficient)
            var notes: [Note] = []
            for assignment in matchedLessonAssignments {
                if let assignmentNotes = assignment.unifiedNotes {
                    notes.append(contentsOf: assignmentNotes)
                }
            }

            // If relationship arrays are not available or incomplete, fetch all notes and filter
            if notes.isEmpty {
                let allNotes = try modelContext.fetch(FetchDescriptor<Note>())
                notes = allNotes.filter { note in
                    // Check via lessonAssignment relationship (preferred)
                    if let noteLessonAssignment = note.lessonAssignment {
                        return matchedIDs.contains(noteLessonAssignment.id)
                    }
                    // Legacy fallback: check via presentation relationship
                    if let notePresentation = note.presentation {
                        return matchedIDs.contains(notePresentation.id)
                    }
                    return false
                }
            } else {
                // De-duplicate in case relationship arrays overlap
                var seenIDs: Set<UUID> = []
                notes = notes.filter { note in
                    if seenIDs.contains(note.id) {
                        return false
                    }
                    seenIDs.insert(note.id)
                    return true
                }
            }

            return notes
        } catch {
            return []
        }
    }
    
    // Get notes from WorkModels associated with this studentLesson
    private var workNotesForThisStudentLesson: [Note] {
        do {
            // Fetch all Notes to avoid SwiftData predicate limitations
            let allNotes = try modelContext.fetch(FetchDescriptor<Note>())
            
            // Convert studentLesson.studentIDs (String array) to UUID set for comparison
            let studentLessonStudentIDs = Set(studentLesson.studentIDs.compactMap { UUID(uuidString: $0) })
            let studentLessonLessonID = studentLesson.lessonID
            
            return allNotes.filter { note in
                // Must have a work relationship
                guard let work = note.work else { return false }
                
                // Work's lessonID must match studentLesson's lessonID
                guard work.lessonID == studentLessonLessonID else { return false }
                
                // Filter by scope to ensure note is relevant to this group
                switch note.scope {
                case .all:
                    return true
                case .student(let id):
                    // Include if studentLesson.studentIDs contains this id
                    return studentLessonStudentIDs.contains(id)
                case .students(let ids):
                    // Include if ANY id in the scope matches ANY studentID in studentLesson
                    return ids.contains { studentLessonStudentIDs.contains($0) }
                }
            }
        } catch {
            return []
        }
    }
    
    // Get lesson-attached notes (not from presentations)
    // Task requirement: Notes where note.studentLesson == current StudentLesson
    private var lessonNotes: [Note] {
        // Use inverse relationship from StudentLesson
        studentLesson.unifiedNotes ?? []
    }
    
    // Get presentation-attached notes
    private var presentationNotes: [Note] {
        presentationNotesForThisLesson
    }
    
    // Get all unified notes (lesson-attached + work-attached + presentation-attached), merged, de-duplicated, and sorted
    private var allUnifiedNotes: [Note] {
        let lessonNotes = self.lessonNotes
        let workNotes = workNotesForThisStudentLesson
        let presentationNotes = self.presentationNotes
        
        // Merge and de-duplicate by note.id (keep first occurrence)
        var seenIDs: Set<UUID> = []
        var merged: [Note] = []
        
        for note in lessonNotes + workNotes + presentationNotes {
            if !seenIDs.contains(note.id) {
                seenIDs.insert(note.id)
                merged.append(note)
            }
        }
        
        // Sort by createdAt descending
        return merged.sorted(by: { $0.createdAt > $1.createdAt })
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
            // Show lesson-attached Note objects
            if !allUnifiedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allUnifiedNotes, id: \.id) { note in
                        unifiedNoteRow(note)
                    }
                }
            }
            
            // Show Presentation Notes section
            if !presentationNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presentation Notes")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    // Show presentation-attached Note objects
                    ForEach(presentationNotes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                        unifiedNoteRow(note)
                    }
                }
            }
            
            // Show legacy string field (if it has content and no other notes)
            if !legacyNotes.trimmed().isEmpty && allUnifiedNotes.isEmpty && presentationNotes.isEmpty {
                TextEditor(text: Binding(
                    get: { legacyNotes },
                    set: { onLegacyNotesChange($0) }
                ))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            } else if allUnifiedNotes.isEmpty && presentationNotes.isEmpty && legacyNotes.trimmed().isEmpty {
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
    
}



