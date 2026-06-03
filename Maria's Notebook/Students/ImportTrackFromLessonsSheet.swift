// ImportTrackFromLessonsSheet.swift
// Sheet for importing a track from lessons organized by area and sequence

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
    @State private var selectedArea: String?
    @State private var selectedSequence: String?
    @State private var trackTitle: String = ""
    @State private var lastDefaultTitle: String = ""
    @State private var isLoading = true
    
    // MARK: - Computed Properties
    private let viewModel = LessonsViewModel()
    
    private var availableAreas: [String] {
        viewModel.areas(from: allLessons)
    }
    
    private var availableSequences: [String] {
        guard let area = selectedArea else { return [] }
        return viewModel.groups(for: area, lessons: allLessons)
    }
    
    private var defaultTitle: String {
        if let area = selectedArea, let sequence = selectedSequence {
            return "\(area) — \(sequence)"
        }
        return ""
    }
    
    private var canImport: Bool {
        selectedArea != nil && selectedSequence != nil && !trackTitle.trimmed().isEmpty
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section("Area") {
                    Picker("Area", selection: $selectedArea) {
                        Text("Select a area").tag(nil as String?)
                        ForEach(availableAreas, id: \.self) { area in
                            Text(area).tag(area as String?)
                        }
                    }
                    .onChange(of: selectedArea) { _, _ in
                        // Reset sequence when area changes
                        selectedSequence = nil
                        updateTitle()
                    }
                }
                
                Section("Sequence") {
                    if selectedArea == nil {
                        Text("Select a area first")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if availableSequences.isEmpty {
                        Text("No groups found for this area")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Sequence", selection: $selectedSequence) {
                            Text("Select a sequence").tag(nil as String?)
                            ForEach(availableSequences, id: \.self) { sequence in
                                Text(sequence).tag(sequence as String?)
                            }
                        }
                        .onChange(of: selectedSequence) { _, _ in
                            updateTitle()
                        }
                    }
                }
                
                Section("Track Title") {
                    TextField("Title", text: $trackTitle)
                }
            }
            .navigationTitle("Import Track from Lessons")
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
        guard let area = selectedArea?.trimmed(),
              let sequence = selectedSequence?.trimmed(),
              !area.isEmpty,
              !sequence.isEmpty else {
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
        
        // In-memory filter to chosen area + sequence using trimmed, case-insensitive comparisons
        let filteredLessons = allLessonsFetched.filter { lesson in
            lesson.area.trimmed().caseInsensitiveCompare(area) == .orderedSame &&
            lesson.sequence.trimmed().caseInsensitiveCompare(sequence) == .orderedSame
        }
        
        // Sort exactly like LessonsViewModel does when selectedSequence != nil:
        // orderInSequence ascending, then name ascending, then id as final tiebreaker
        let sortedLessons = filteredLessons.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence {
                return lhs.orderInSequence < rhs.orderInSequence
            }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder == .orderedSame {
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
            return nameOrder == .orderedAscending
        }
        
        // Track and TrackStep live in the shared store. If we're
        // creating them before a CKShare exists, SharedStoreZoneRepair
        // will need to attach them once the lead guide shares the
        // classroom. Log a breadcrumb so the next investigation can
        // trace the origin.
        if !SharedStoreZoneRepair.shared.hasActiveShare {
            let warnMsg = "Importing track from lessons into shared store with no active CKShare " +
                "(title=\(title), steps=\(sortedLessons.count))"
            Self.logger.warning("\(warnMsg, privacy: .public)")
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
