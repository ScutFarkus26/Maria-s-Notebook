import OSLog
import SwiftUI
import CoreData
import PhotosUI

// Conditional Import for Apple Intelligence features
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
class QuickNoteViewModel {
    private static let logger = Logger.notes

    // MARK: - Properties

    // Content
    var bodyText: String = ""
    /// Her cursor in the editor, kept in place when auto-tidy rewrites the text.
    var textSelection: TextSelection?
    var tags: [String] = []
    var needsFollowUp: Bool = false
    var selectedStudentIDs: Set<UUID> = []
    var includeInReport: Bool = false
    var noteDate: Date = Date()
    var showingTagPicker: Bool = false

    // Attachments
    var selectedPhotoItem: PhotosPickerItem?
    var attachedImage: PlatformImage?
    var attachedImagePath: String?
    /// The picked photo still being loaded and stored (an iCloud Photos
    /// original can take seconds). Save waits for it (`canSave`).
    var loadingPhotoItem: PhotosPickerItem?
    var isLoadingPhoto: Bool { loadingPhotoItem != nil }
    /// How long Save waits for a picked photo before giving up on it.
    var photoLoadLimit: Duration = .seconds(30)
    /// Shown under the note when a picked photo didn't arrive in time.
    var photoLoadMessage: String?

    // AI & Analysis State
    var detectedCandidateIDs: Set<UUID> = []
    var isProcessingAI: Bool = false
    var aiError: String?
    /// Children she took off this note. The name finder never puts them back:
    /// it used to re-add a removed chip on the next keystroke. Changed only
    /// through `setSelectedStudents` (QuickNoteViewModel+Saving.swift).
    var removedStudentIDs: Set<UUID> = []

    // Saving (QuickNoteViewModel+Saving.swift)
    /// Shown when Save fails; the sheet stays open with her text.
    var saveErrorMessage: String?
    /// Set once the note is saved, so closing the sheet keeps its photo.
    var didSave = false

    // UI State
    var isShowingStudentPicker: Bool = false
    var isShowingCamera: Bool = false

    // CDTrackEntity Context
    var selectedEnrollmentID: UUID?

    // CDLesson Context
    var selectedLessonID: UUID?
    var isShowingLessonPicker: Bool = false
    
    // MARK: - Dependencies
    private let tagger = StudentTagger()
    let initialStudentID: UUID?

    // MARK: - Debouncing
    private var analysisTask: Task<Void, Never>?
    private var isApplyingReplacements: Bool = false
    private var lastReplacementText: String?

    // MARK: - Initialization

    init(initialStudentIDs: Set<UUID> = [], initialBodyText: String = "", initialTags: [String] = []) {
        self.initialStudentID = initialStudentIDs.first
        self.selectedStudentIDs = initialStudentIDs

        if !initialBodyText.isEmpty {
            self.bodyText = initialBodyText
        }
        if !initialTags.isEmpty {
            self.tags = initialTags
        }
    }
    
    // MARK: - Public Methods
    
    func setupInitialState() {
        if let initialID = initialStudentID {
            selectedStudentIDs.insert(initialID)
        }
    }
    
    func analyzeText(_ text: String, students: [CDStudent]) {
        // Don't analyze if we're currently applying replacements to avoid infinite loops
        guard !isApplyingReplacements else { return }
        
        // Don't analyze if this text matches what we just replaced (prevents re-analysis of replacement result)
        if let lastReplacement = lastReplacementText, text == lastReplacement {
            lastReplacementText = nil // Clear after one check
            return
        }
        
        // Cancel previous analysis task
        analysisTask?.cancel()
        
        // If we're in the middle of typing a word (not at word boundary), clear suggestions
        // This prevents showing suggestions for incomplete words like "Mar" when typing "Maria"
        if !isAtWordBoundary(text) && !text.isEmpty {
            detectedCandidateIDs = []
        }
        
        // Debounce the analysis to wait for complete words
        analysisTask = Task {
            // Wait for a delay to allow the user to finish typing the complete word
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                // Task was cancelled, exit early
                return
            }

            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            let studentData = getStudentData(from: students)
            let result = await tagger.findStudentMatches(in: text, studentData: studentData)

            // Auto-add exact and unique matches not already chosen or taken off
            let matches = self.newMatches(from: result)
            if !matches.add.isEmpty {
                adaptiveWithAnimation {
                    self.selectedStudentIDs.formUnion(matches.add)
                }
            }
            self.detectedCandidateIDs = matches.suggest
            
            // Apply text replacements for exact matches (QuickNoteAutoTidy),
            // keeping her cursor where she was typing
            if !result.replacements.isEmpty {
                // Set flag to prevent re-analysis during replacement
                self.isApplyingReplacements = true

                let cursor = QuickNoteAutoTidy.cursorOffset(of: self.textSelection, in: self.bodyText)
                // Only update if text actually changed
                if let tidied = QuickNoteAutoTidy.apply(result.replacements, to: self.bodyText, cursor: cursor) {
                    // Store the updated text to check against in next analysis
                    self.lastReplacementText = tidied.text

                    adaptiveWithAnimation {
                        self.bodyText = tidied.text
                    }
                    if let offset = tidied.cursor {
                        self.textSelection = QuickNoteAutoTidy.selection(at: offset, in: tidied.text)
                    }

                    // Reset flag after a delay to allow onChange to complete
                    // (strong self: holds the VM for at most 100ms and guarantees the flag resets)
                    Task { [self] in
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                        } catch {
                            // Task was cancelled, ignored
                        }
                        self.isApplyingReplacements = false
                    }
                } else {
                    // No changes, reset flag immediately
                    self.isApplyingReplacements = false
                }
            }
        }
    }
    
    func formatNamesLocally(students: [CDStudent]) {
        guard !bodyText.isEmpty else { return }
        isProcessingAI = true // Show spinner
        
        let studentData = getStudentData(from: students)
        let currentText = bodyText
        Task { [weak self] in
            guard let self else { return }
            // Use the actor to perform robust string replacement
            let newText = await tagger.formatStudentNames(in: currentText, studentData: studentData)

            adaptiveWithAnimation {
                self.bodyText = newText
                self.isProcessingAI = false
            }
            // A whole new text: the cursor goes to its end, never left
            // pointing into the old one.
            self.textSelection = QuickNoteAutoTidy.selection(at: newText.utf16.count, in: newText)
        }
    }
    
    func getDisplayName(for student: CDStudent, students: [CDStudent]) -> String {
        // If there are other students in the full roster with the same first name, use Last Initial
        let duplicateCount = students.filter { $0.firstName.lowercased() == student.firstName.lowercased() }.count
        if duplicateCount > 1 {
            return student.shortName
        }
        return student.firstName
    }
    
    // MARK: - Private Methods
    
    private func getStudentData(from students: [CDStudent]) -> [StudentData] {
        return students.compactMap { student in
            guard let id = student.id else { return nil }
            return StudentData(
                id: id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname
            )
        }
    }
    
    /// Checks if the text ends at a word boundary (space, punctuation, or end of text)
    /// Returns true if the last character is whitespace, punctuation, or if text is empty
    private func isAtWordBoundary(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        
        guard let lastChar = text.last else { return true }
        return lastChar.isWhitespace || lastChar.isPunctuation
    }
    
    // MARK: - Apple Intelligence
    
    #if ENABLE_FOUNDATION_MODELS
    func runAI(instruction: String) {
        guard !bodyText.isEmpty else { return }
        isProcessingAI = true

        Task { [weak self] in
            await self?.processAIRequest(instruction: instruction)
        }
    }
    
    private func processAIRequest(instruction: String) async {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                self.aiError = AppleIntelligenceMessages.unavailableMessage(
                    for: SystemLanguageModel.default.availability
                ) ?? AppleIntelligenceMessages.notAvailable
                self.isProcessingAI = false
                return
            }
            do {
                let session = LanguageModelSession()
                let prompt = AIPrompts.processQuickNote(instruction: instruction, text: bodyText)
                let response = try await session.respond(to: prompt)
                
                adaptiveWithAnimation {
                    self.bodyText = response.content
                    self.isProcessingAI = false
                }
                self.textSelection = QuickNoteAutoTidy.selection(
                    at: response.content.utf16.count, in: response.content
                )
            } catch let error as LanguageModelError {
                self.aiError = Self.userMessage(for: error)
                self.isProcessingAI = false
            } catch {
                self.aiError = AppErrorMessages.aiMessage(for: error)
                self.isProcessingAI = false
            }
        } else {
            self.isProcessingAI = false
        }
        #else
        self.isProcessingAI = false
        #endif
    }
    
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    static func userMessage(for error: LanguageModelError) -> String {
        AppleIntelligenceMessages.message(
            for: error, tooLong: "This note is too long for Apple Intelligence. Try a shorter note."
        )
    }
    #endif
    #endif
}
