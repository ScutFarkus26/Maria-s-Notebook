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

    @Guide(description: "CDStudent names mentioned in the note; empty means all students")
    var studentIdentifiers: [String]
}
#endif

/// A unified note editor that works for all note types in the app
struct UnifiedNoteEditor: View {
    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext

    // MARK: - Context Configuration
    enum NoteContext {
        case general
        case lesson(CDLesson)
        case work(CDWorkModel)
        case presentation(CDLessonAssignment)
        case attendance(CDAttendanceRecord)
        case workCheckIn(CDWorkCheckIn)
        case workCompletion(CDWorkCompletionRecord)
        case studentMeeting(CDStudentMeeting)
        case projectSession(CDProjectSession)
        case communityTopic(CDCommunityTopicEntity)
        case reminder(CDReminder)
        case schoolDayOverride(CDSchoolDayOverride)
        case goingOut(CDGoingOut)
        case transitionPlan(CDTransitionPlan)
    }

    // MARK: - Properties
    let context: NoteContext
    let initialNote: CDNote?
    let onSave: (CDNote) -> Void
    let onCancel: () -> Void

    // MARK: - Query
    @FetchRequest(sortDescriptors: CDStudent.sortByName)var studentsRaw: FetchedResults<CDStudent>
    var students: [CDStudent] { studentsRaw.filter(\.isEnrolled) }

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
    @State var showingSuggestionSheet: Bool = false
    @State var proposedTags: [String] = []
    @State var proposedStudentIDs: [UUID] = []
    @State var suggestionError: String?
    #endif

    @State var aiTriggerCounter: Int = 0

    let tagger = StudentTagger()
    @State private var nameDetectionTask: Task<Void, Never>?

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
                    if !proposedStudentIDs.isEmpty { self.selectedStudentIDs = Set(proposedStudentIDs) }
                    showingSuggestionSheet = false
                },
                onCancel: {
                    showingSuggestionSheet = false
                }
            )
        }
        .alert("AI Suggestion Error", isPresented: Binding(
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
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
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
        if shouldShowStudentSelection {
            nameDetectionTask?.cancel()
            nameDetectionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                await analyzeTextForNames(newText)
            }
        }
    }
}
