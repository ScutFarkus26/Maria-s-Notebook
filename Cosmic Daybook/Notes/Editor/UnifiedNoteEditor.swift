// UnifiedNoteEditor.swift
// A unified note editor that works for all note types in the app
// Based on QuickNoteSheet but supports all contexts
//
// Split into multiple files for maintainability:
// - UnifiedNoteEditor.swift (this file) - Main view structure and body
// - NoteEditorSections.swift - View sections (tags, note body, photos, etc.)
// - NoteEditorStudentSelection.swift - CDStudent selection UI (surfacing banner, student picker)
// - NoteEditorHelpers.swift - Helper methods and computed properties
// - NoteEditorSaveLogic.swift - Save functionality and relationship mapping
// - NoteEditorAISuggestion.swift - AI suggestion functionality
// - TemplatePickerView.swift - Template picker standalone view
// - SmartTextEditor.swift - Smart text editor component

import SwiftUI
import CoreData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "Tag suggestions for a classroom note")
struct NoteTagSuggestion {
    // swiftlint:disable:next line_length
    @Guide(description: "Suggested tag names, e.g. Academic, Behavioral, Social, Emotional, Health, Attendance, or any relevant custom tag")
    var suggestedTags: [String]

    @Guide(description: "Student names mentioned in the note; empty means all students")
    var studentIdentifiers: [String]
}
#endif

/// A unified note editor that works for all note types in the app
struct UnifiedNoteEditor: View {
    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies

    // MARK: - Context Configuration
    enum NoteContext {
        case general
        case lesson(CDLesson)
        case work(CDWorkModel)
        case presentation(CDLessonAssignment)
        case workCheckIn(CDWorkCheckIn)
        case workCompletion(CDWorkCompletionRecord)
        case studentMeeting(CDStudentMeeting)
        case projectSession(CDProjectSession)
        case communityTopic(CDCommunityTopicEntity)
        case reminder(CDReminder)
        case schoolDayOverride(CDSchoolDayOverride)
        case goingOut(CDGoingOut)
    }

    // MARK: - Properties
    let context: NoteContext
    let initialNote: CDNote?
    let onSave: (CDNote) -> Void
    let onCancel: () -> Void

    // MARK: - Query
    var students: [CDStudent] { dependencies.roster.enrolled }

    // MARK: - State
    @State var selectedStudentIDs: Set<UUID> = []
    @State var detectedStudentIDs: Set<UUID> = []
    @State var tags: [String] = []
    @State var bodyText: String = ""
    @State var includeInReport: Bool = false
    @State var needsFollowUp: Bool = false
    @State var showingTagPicker: Bool = false
    @State var showingStudentPicker: Bool = false
    @State var selectedPhoto: PhotosPickerItem?

    #if os(iOS)
    @State var showingCamera: Bool = false
    #endif

    #if os(macOS)
    @State var selectedImage: NSImage?
    #else
    @State var selectedImage: UIImage?
    #endif

    @State var imagePath: String?
    /// Tracks the original image path when editing an existing note, for cleanup when image changes
    @State var originalImagePath: String?

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State var isSuggesting: Bool = false
    @State var isDescribingPhoto: Bool = false
    @State var showingSuggestionSheet: Bool = false
    @State var proposedTags: [String] = []
    @State var proposedStudentIDs: [UUID] = []
    @State var suggestionError: String?
    #endif

    @State var aiTriggerCounter: Int = 0

    /// The note's text when the editor opened ("" for a new note): what
    /// counts as unsaved, and text the name finder leaves alone.
    @State var openedBodyText: String?
    /// Shown when Save fails; the editor stays open with her changes.
    @State var saveErrorMessage: String?
    @State var isConfirmingDiscard = false
    /// Children she took off while editing; the name finder leaves them off
    /// (`chooseStudents`, `NoteEditorChildChoice`).
    @State var deselectedStudentIDs: Set<UUID> = []

    let tagger = StudentTagger()
    @State private var nameDetectionTask: Task<Void, Never>?
    /// Children an opened note's own text names. Editing the note doesn't add
    /// them: she chose its children when she wrote it.
    @State private var openedTextNames: Set<UUID> = []

    // MARK: - Body

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        .sheet(isPresented: $showingSuggestionSheet) {
            SuggestionPreviewSheet(
                proposedTags: proposedTags,
                proposedStudentIDs: proposedStudentIDs,
                allStudents: students,
                onApply: { appliedTags in
                    // Merge suggested tags with existing, avoiding duplicates
                    for tag in appliedTags where !self.tags.contains(tag) {
                        self.tags.append(tag)
                    }
                    // Adds the children it named to hers; it used to replace them.
                    chooseStudents(selectedStudentIDs.union(proposedStudentIDs))
                    showingSuggestionSheet = false
                },
                onCancel: {
                    showingSuggestionSheet = false
                }
            )
        }
        .alert("Apple Intelligence Couldn't Help", isPresented: Binding(
            get: { suggestionError != nil },
            set: { if !$0 { suggestionError = nil } }
        )) {
            Button("OK") { suggestionError = nil }
        } message: {
            if let error = suggestionError {
                Text(error)
            }
        }
#endif
        .onAppear {
            setupInitialState()
            openedBodyText = bodyText
        }
        .task {
            guard let note = initialNote, shouldShowStudentSelection else { return }
            openedTextNames = await namesMentioned(in: note.body)
        }
        // A swipe down or a tap outside used to throw her changes away.
        .interactiveDismissDisabled(hasUnsavedChanges)
        .confirmationDialog(
            "Discard your changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { discardAndClose() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("What you changed here hasn't been saved.")
        }
        .alert("Couldn't Save the Note", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? NoteEditorSave.notSavedMessage)
        }
        .onChange(of: bodyText) { _, newText in
            handleBodyTextChange(newText)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            handlePhotoChange(newItem)
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $selectedImage) { img in
                if let img {
                    handleCameraImage(img)
                }
            }
        }
        #endif
    }

    // MARK: - Platform Layouts

    #if os(macOS)
    private var macOSLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerView
            ScrollView {
                mainContentCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 480, minHeight: 460, idealHeight: 540)
        .presentationSizingFitted()
    }
    #endif

    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mainContentCard
                }
                .padding(24)
            }
            .dismissKeyboardOnScroll()
            .navigationTitle(contextTitle)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    #endif

    // MARK: - Event Handlers

    private func handleBodyTextChange(_ newText: String) {
        // Opening a note put its own text through the name finder, which
        // added every child it mentions; only what she types now counts.
        if initialNote != nil, newText == openedBodyText { return }
        if shouldShowStudentSelection {
            nameDetectionTask?.cancel()
            nameDetectionTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                let before = selectedStudentIDs
                await analyzeTextForNames(newText)
                // A child she took off, or one the opened note already named,
                // isn't put back by what she types.
                let kept = NoteEditorChildChoice.afterNameFinder(
                    before: before, after: selectedStudentIDs,
                    deselected: deselectedStudentIDs, openedTextNames: openedTextNames
                )
                if kept != selectedStudentIDs { selectedStudentIDs = kept }
            }
        }
    }

    /// The children the name finder would add for `text`.
    private func namesMentioned(in text: String) async -> Set<UUID> {
        let studentData = students.compactMap { student -> StudentData? in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id, firstName: student.firstName, lastName: student.lastName, nickname: student.nickname
            )
        }
        let result = await tagger.findStudentMatches(in: text, studentData: studentData)
        return result.exact.union(result.autoSelect)
    }
}
