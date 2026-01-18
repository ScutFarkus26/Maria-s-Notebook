// UnifiedNoteEditor.swift
// A unified note editor that works for all note types in the app
// Based on QuickNoteSheet but supports all contexts
//
// Split into multiple files for maintainability:
// - UnifiedNoteEditor.swift (this file) - Main view structure and body
// - NoteEditorSections.swift - All view sections (student selection, category, etc.)
// - NoteEditorHelpers.swift - Helper methods and computed properties
// - NoteEditorSaveLogic.swift - Save functionality and relationship mapping
// - NoteEditorAISuggestion.swift - AI suggestion functionality
// - SmartTextEditor.swift - Smart text editor component

import SwiftUI
import SwiftData
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
@Generable(description: "Classification for a single note")
struct NoteClassificationSuggestion {
    @Guide(description: "One of: academic, behavioral, social, emotional, health, attendance, general")
    var category: String

    @Guide(description: "IDs or names indicating student-specific scope; empty means all")
    var studentIdentifiers: [String]
}
#endif

/// A unified note editor that works for all note types in the app
struct UnifiedNoteEditor: View {
    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    // MARK: - Context Configuration
    enum NoteContext {
        case general
        case lesson(Lesson)
        case work(WorkModel)
        case studentLesson(StudentLesson)
        case presentation(Presentation)
        case attendance(AttendanceRecord)
        case workCheckIn(WorkCheckIn)
        case workCompletion(WorkCompletionRecord)
        case workPlanItem(WorkPlanItem)
        case studentMeeting(StudentMeeting)
        case projectSession(ProjectSession)
        case communityTopic(CommunityTopic)
        case reminder(Reminder)
        case schoolDayOverride(SchoolDayOverride)
    }

    // MARK: - Properties
    let context: NoteContext
    let initialNote: Note?
    let onSave: (Note) -> Void
    let onCancel: () -> Void

    // MARK: - Query
    @Query(sort: [
        SortDescriptor(\Student.firstName),
        SortDescriptor(\Student.lastName)
    ]) var students: [Student]

    // MARK: - State
    @State var selectedStudentIDs: Set<UUID> = []
    @State var detectedStudentIDs: Set<UUID> = []
    @State var category: NoteCategory = .general
    @State var bodyText: String = ""
    @State var includeInReport: Bool = false
    @State var showingStudentPicker: Bool = false
    @State var selectedPhoto: PhotosPickerItem? = nil

    #if os(iOS)
    @State var showingCamera: Bool = false
    #endif

    #if os(macOS)
    @State var selectedImage: NSImage? = nil
    #else
    @State var selectedImage: UIImage? = nil
    #endif

    @State var imagePath: String? = nil

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State var isSuggesting: Bool = false
    @State var showingSuggestionSheet: Bool = false
    @State var proposedCategory: NoteCategory? = nil
    @State var proposedStudentIDs: [UUID] = []
    @State var suggestionError: String? = nil
    #endif

    @State var aiTriggerCounter: Int = 0

    let tagger = StudentTagger()
    @State var nameDetectionTask: Task<Void, Never>? = nil

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
                proposedCategory: proposedCategory,
                proposedStudentIDs: proposedStudentIDs,
                allStudents: students,
                onApply: {
                    if let cat = proposedCategory { self.category = cat }
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
                if let img = img {
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
        .frame(width: 480, height: 560)
        .presentationSizingFitted()
    }
    #endif

    private var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mainContentCard
                }
                .padding(24)
            }
            .navigationTitle(contextTitle)
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Event Handlers

    private func handleBodyTextChange(_ newText: String) {
        if shouldShowStudentSelection {
            nameDetectionTask?.cancel()
            nameDetectionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await analyzeTextForNames(newText)
            }
        }
    }
}
