// TrackDetailView.swift
// Detail view for editing a track and managing its steps

import SwiftUI
import SwiftData

struct TrackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var track: Track
    @State private var showingLessonPicker = false
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var allLessons: [Lesson]
    
    private var orderedSteps: [TrackStep] {
        let steps = track.steps ?? []
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
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(orderedSteps) { step in
                        StepRow(step: step, allLessons: allLessons)
                    }
                    .onMove(perform: moveSteps)
                }
            }
        }
        .navigationTitle(track.title.isEmpty ? "Track" : track.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        guard let lessonID = lessonID else { return }
        
        let existingSteps = track.steps ?? []
        let nextOrderIndex = existingSteps.isEmpty ? 0 : (existingSteps.map { $0.orderIndex }.max() ?? -1) + 1
        
        let newStep = TrackStep(
            track: track,
            orderIndex: nextOrderIndex,
            lessonTemplateID: lessonID
        )
        modelContext.insert(newStep)
        
        if track.steps == nil {
            track.steps = []
        }
        track.steps = (track.steps ?? []) + [newStep]
        
        saveContext()
    }
    
    private func moveSteps(from source: IndexSet, to destination: Int) {
        var steps = orderedSteps
        steps.move(fromOffsets: source, toOffset: destination)
        
        // Update orderIndex for all steps
        for (index, step) in steps.enumerated() {
            step.orderIndex = index
        }
        
        saveContext()
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save track: \(error)")
        }
    }
}

private struct StepRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var step: TrackStep
    let allLessons: [Lesson]
    
    private var lesson: Lesson? {
        guard let lessonID = step.lessonTemplateID else { return nil }
        return allLessons.first { $0.id == lessonID }
    }
    
    var body: some View {
        HStack {
            Text("\(step.orderIndex + 1).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            if let lesson = lesson {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(.body)
                    
                    if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                        Text("\(lesson.subject) · \(lesson.group)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Unknown Lesson")
                    .foregroundColor(.secondary)
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
    @Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]
    
    private var filteredLessons: [Lesson] {
        if searchText.isEmpty {
            return lessons
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
                                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                if !lesson.subject.isEmpty || !lesson.group.isEmpty {
                                    Text("\(lesson.subject) · \(lesson.group)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Lesson")
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

