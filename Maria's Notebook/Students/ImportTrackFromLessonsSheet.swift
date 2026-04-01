// ImportTrackFromLessonsSheet.swift
// Sheet for importing a track from lessons organized by subject and group

import OSLog
import SwiftUI
import CoreData

struct ImportTrackFromLessonsSheet: View {
    private static let logger = Logger.students

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Callback
    var onImport: ((UUID) -> Void)?
    
    // MARK: - State
    @State private var allLessons: [CDLesson] = []
    @State private var selectedSubject: String?
    @State private var selectedGroup: String?
    @State private var trackTitle: String = ""
    @State private var lastDefaultTitle: String = ""
    @State private var isLoading = true
    
    // MARK: - Computed Properties
    private let viewModel = LessonsViewModel()
    
    private var availableSubjects: [String] {
        viewModel.subjects(from: allLessons)
    }
    
    private var availableGroups: [String] {
        guard let subject = selectedSubject else { return [] }
        return viewModel.groups(for: subject, lessons: allLessons)
    }
    
    private var defaultTitle: String {
        if let subject = selectedSubject, let group = selectedGroup {
            return "\(subject) — \(group)"
        }
        return ""
    }
    
    private var canImport: Bool {
        selectedSubject != nil && selectedGroup != nil && !trackTitle.trimmed().isEmpty
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    Picker("Subject", selection: $selectedSubject) {
                        Text("Select a subject").tag(nil as String?)
                        ForEach(availableSubjects, id: \.self) { subject in
                            Text(subject).tag(subject as String?)
                        }
                    }
                    .onChange(of: selectedSubject) { _, _ in
                        // Reset group when subject changes
                        selectedGroup = nil
                        updateTitle()
                    }
                }
                
                Section("Group") {
                    if selectedSubject == nil {
                        Text("Select a subject first")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if availableGroups.isEmpty {
                        Text("No groups found for this subject")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Group", selection: $selectedGroup) {
                            Text("Select a group").tag(nil as String?)
                            ForEach(availableGroups, id: \.self) { group in
                                Text(group).tag(group as String?)
                            }
                        }
                        .onChange(of: selectedGroup) { _, _ in
                            updateTitle()
                        }
                    }
                }
                
                Section("CDTrackEntity Title") {
                    TextField("Title", text: $trackTitle)
                }
            }
            .navigationTitle("Import CDTrackEntity from Lessons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importTrack()
                    }
                    .disabled(!canImport)
                }
            }
            .task {
                loadLessons()
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            #endif
        }
    }
    
    // MARK: - Data Loading
    private func loadLessons() {
        do {
            let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
            allLessons = try viewContext.fetch(descriptor)
        } catch {
            allLessons = []
        }
        isLoading = false
    }
    
    // MARK: - Helpers
    private func updateTitle() {
        let newDefault = defaultTitle
        // Only update if title is empty, matches the last default, or ends with " — " (incomplete default)
        if trackTitle.isEmpty || trackTitle == lastDefaultTitle || trackTitle.hasSuffix(" — ") {
            trackTitle = newDefault
        }
        lastDefaultTitle = newDefault
    }
    
    // MARK: - Import Logic
    private func importTrack() {
        guard let subject = selectedSubject?.trimmed(),
              let group = selectedGroup?.trimmed(),
              !subject.isEmpty,
              !group.isEmpty else {
            return
        }
        
        let title = trackTitle.trimmed()
        guard !title.isEmpty else { return }
        
        // Fetch all lessons (no predicate)
        let allLessonsFetched: [CDLesson]
        do {
            let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
            allLessonsFetched = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error)")
            return
        }
        
        // In-memory filter to chosen subject + group using trimmed, case-insensitive comparisons
        let filteredLessons = allLessonsFetched.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(subject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(group) == .orderedSame
        }
        
        // Sort exactly like LessonsViewModel does when selectedGroup != nil:
        // orderInGroup ascending, then name ascending, then id as final tiebreaker
        let sortedLessons = filteredLessons.sorted { lhs, rhs in
            if lhs.orderInGroup != rhs.orderInGroup {
                return lhs.orderInGroup < rhs.orderInGroup
            }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder == .orderedSame {
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
            return nameOrder == .orderedAscending
        }
        
        // Create new CDTrackEntity
        let newTrack = CDTrackEntity(context: viewContext)
        newTrack.title = title

        // Create CDTrackStep for each lesson
        var steps: [CDTrackStepEntity] = []
        for (index, lesson) in sortedLessons.enumerated() {
            let step = CDTrackStepEntity(context: viewContext)
            step.orderIndex = Int64(index)
            step.lessonTemplateID = lesson.id
            steps.append(step)
        }

        // Set the steps relationship
        newTrack.steps = NSSet(array: steps)
        
        // Save
        do {
            try viewContext.save()
            // Call callback with the new track ID
            if let trackID = newTrack.id { onImport?(trackID) }
            dismiss()
        } catch {
            Self.logger.warning("Failed to import track: \(error)")
        }
    }
}
