// ParshaLessonEditorSheet.swift
// Create or edit a parsha-tagged CDLesson. Saves via LessonRepository and then sets
// the parsha-specific fields before persisting.

import SwiftUI
import CoreData
import OSLog

struct ParshaLessonEditorSheet: View {
    let parshaKey: String
    let existingLesson: CDLesson?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var name: String = ""
    @State private var selectedParshaKey: String
    @State private var ageRange: String = ""
    @State private var teacherNotes: String = ""
    @State private var derivedFromLessonID: UUID?
    @State private var showAllLessonsForDerivation: Bool = false
    @State private var showingDerivedPicker: Bool = false

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var allLessons: FetchedResults<CDLesson>

    init(parshaKey: String, existingLesson: CDLesson?) {
        self.parshaKey = parshaKey
        self.existingLesson = existingLesson
        selectedParshaKey = existingLesson?.parshaKey ?? parshaKey
    }

    private var candidateDerivedLessons: [CDLesson] {
        let base = Array(allLessons).filter { $0.id != existingLesson?.id }
        if showAllLessonsForDerivation { return base }
        return base.filter { $0.lessonFormatRaw == "art" }
    }

    private var derivedLessonName: String? {
        guard let id = derivedFromLessonID else { return nil }
        return allLessons.first(where: { $0.id == id })?.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson") {
                    TextField("Name", text: $name)

                    Picker("Parsha", selection: $selectedParshaKey) {
                        ForEach(HebrewParshaService.allParshaKeys, id: \.self) { key in
                            Text(HebrewParshaService.displayName(forKey: key)).tag(key)
                        }
                    }

                    TextField("Age (e.g. 3\u{2013}5, Lower El)", text: $ageRange)
                }

                Section {
                    Button {
                        showingDerivedPicker = true
                    } label: {
                        HStack {
                            Text("Based on art lesson")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(derivedLessonName ?? "None")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if derivedFromLessonID != nil {
                        Button(role: .destructive) {
                            derivedFromLessonID = nil
                        } label: {
                            Text("Clear art lesson")
                        }
                    }
                } header: {
                    Text("Art Lesson (optional)")
                } footer: {
                    Text("Tag a technique from your art-lesson library that this parsha lesson draws on.")
                }

                Section("Notes") {
                    TextEditor(text: $teacherNotes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(existingLesson == nil ? "New Parsha Lesson" : "Edit Parsha Lesson")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingLesson == nil ? "Add" : "Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed().isEmpty)
                }
            }
            .sheet(isPresented: $showingDerivedPicker) {
                DerivedLessonPickerSheet(
                    candidates: candidateDerivedLessons,
                    selectedID: $derivedFromLessonID,
                    showAll: $showAllLessonsForDerivation
                )
            }
            .onAppear(perform: hydrate)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func hydrate() {
        guard let existing = existingLesson else { return }
        name = existing.name
        ageRange = existing.ageRange
        teacherNotes = existing.teacherNotes
        derivedFromLessonID = existing.derivedFromLessonID.flatMap(UUID.init(uuidString:))
    }

    private func save() {
        let trimmedName = name.trimmed()
        guard !trimmedName.isEmpty else { return }
        let repo = LessonRepository(context: viewContext, saveCoordinator: saveCoordinator)

        let lesson: CDLesson
        if let existing = existingLesson {
            lesson = existing
            lesson.name = trimmedName
            lesson.ageRange = ageRange.trimmed()
            lesson.teacherNotes = teacherNotes
        } else {
            lesson = repo.createLesson(
                name: trimmedName,
                area: "Parsha",
                ageRange: ageRange.trimmed(),
                teacherNotes: teacherNotes
            )
        }
        lesson.parshaKey = selectedParshaKey
        lesson.derivedFromLessonID = derivedFromLessonID?.uuidString

        _ = repo.save(reason: existingLesson == nil ? "Add parsha lesson" : "Update parsha lesson")
        dismiss()
    }
}

private struct DerivedLessonPickerSheet: View {
    let candidates: [CDLesson]
    @Binding var selectedID: UUID?
    @Binding var showAll: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    private var filtered: [CDLesson] {
        let query = search.trimmed().lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show all lessons", isOn: $showAll)
                }
                Section {
                    if filtered.isEmpty {
                        Text("No lessons available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered, id: \.id) { lesson in
                            Button {
                                selectedID = lesson.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lesson.name)
                                            .foregroundStyle(.primary)
                                        if !lesson.area.isEmpty {
                                            Text(lesson.area)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedID == lesson.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Art Lesson")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
        #endif
    }
}
