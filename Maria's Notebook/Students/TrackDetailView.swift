// TrackDetailView.swift
// Detail view for editing a track and managing its steps

import OSLog
import SwiftUI
import CoreData

struct TrackDetailView: View {
    private static let logger = Logger.students

    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var track: CDTrackEntity
    @State private var showingLessonPicker = false
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var allLessons: FetchedResults<CDLesson>
    
    private var orderedSteps: [CDTrackStep] {
        let steps = (track.steps as? Set<CDTrackStep>) ?? []
        return steps.sorted { $0.orderIndex < $1.orderIndex }
    }
    
    var body: some View {
        Form {
            Section("Track") {
                TextField("Title", text: $track.title)
            }
            
            Section("Steps") {
                if orderedSteps.isEmpty {
                    Text("No steps yet. Add a step to get started.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(orderedSteps) { step in
                        StepRow(step: step, allLessons: Array(allLessons))
                    }
                    .onMove(perform: moveSteps)
                }
            }
        }
        .navigationTitle(track.title.isEmpty ? "Track" : track.title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLessonPicker = true
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLessonPicker) {
            LessonPickerSheet { lessonID in
                addStep(for: lessonID)
            }
        }
        .onChange(of: track.title) { _, _ in
            saveContext()
        }
    }
    
    private func addStep(for lessonID: UUID?) {
        guard let lessonID else { return }

        let existingSteps = (track.steps?.allObjects as? [CDTrackStepEntity]) ?? []
        let nextOrderIndex = existingSteps.isEmpty ? Int64(0) : (existingSteps.map(\.orderIndex).max() ?? -1) + 1

        let newStep = CDTrackStepEntity(context: viewContext)
        newStep.track = track
        newStep.orderIndex = nextOrderIndex
        newStep.lessonTemplateID = lessonID

        track.addToSteps(newStep)
        
        saveContext()
    }
    
    private func moveSteps(from source: IndexSet, to destination: Int) {
        var steps = orderedSteps
        steps.move(fromOffsets: source, toOffset: destination)
        
        // Update orderIndex for all steps
        for (index, step) in steps.enumerated() {
            step.orderIndex = Int64(index)
        }
        
        saveContext()
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save track: \(error)")
        }
    }
}

private struct StepRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var step: CDTrackStep
    let allLessons: [CDLesson]
    
    private var lesson: CDLesson? {
        guard let lessonID = step.lessonTemplateID else { return nil }
        return allLessons.first { $0.id == lessonID }
    }
    
    var body: some View {
        HStack {
            Text("\(step.orderIndex + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            if let lesson {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.name.isEmpty ? "Untitled CDLesson" : lesson.name)
                        .font(.body)
                    
                    if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                        Text("\(lesson.subject) · \(lesson.group)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Unknown CDLesson")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct LessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (UUID?) -> Void
    
    @State private var searchText: String = ""
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var lessons: FetchedResults<CDLesson>
    
    private var filteredLessons: [CDLesson] {
        if searchText.isEmpty {
            return Array(lessons)
        }
        return lessons.filter { lesson in
            lesson.name.localizedCaseInsensitiveContains(searchText) ||
            lesson.subject.localizedCaseInsensitiveContains(searchText) ||
            lesson.group.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search lessons...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                List {
                    ForEach(filteredLessons) { lesson in
                        Button {
                            onSelect(lesson.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lesson.name.isEmpty ? "Untitled CDLesson" : lesson.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                
                                if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                                    Text("\(lesson.subject) · \(lesson.group)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select CDLesson")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
        }
    }
}
