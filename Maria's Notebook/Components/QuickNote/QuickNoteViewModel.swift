// swiftlint:disable file_length
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
@MainActor
// swiftlint:disable:next type_body_length
class QuickNoteViewModel {
    private static let logger = Logger.notes

    // MARK: - Properties

    // Content
    var bodyText: String = ""
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

    // AI & Analysis State
    var detectedCandidateIDs: Set<UUID> = []
    var isProcessingAI: Bool = false
    var aiError: String?

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
    
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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
            
            // Auto-add exact matches that are not already selected
            let newExacts = result.exact.subtracting(self.selectedStudentIDs)
            if !newExacts.isEmpty {
                adaptiveWithAnimation {
                    self.selectedStudentIDs.formUnion(newExacts)
                }
            }

            // Auto-select unique matches (autoSelect set from enhanced detection)
            let newAutoSelects = result.autoSelect.subtracting(self.selectedStudentIDs)
            if !newAutoSelects.isEmpty {
                adaptiveWithAnimation {
                    self.selectedStudentIDs.formUnion(newAutoSelects)
                }
            }
            
            // Only suggest fuzzy matches that are not already selected
            self.detectedCandidateIDs = result.fuzzy.subtracting(self.selectedStudentIDs)
            
            // Apply text replacements for exact matches
            if !result.replacements.isEmpty {
                // Set flag to prevent re-analysis during replacement
                self.isApplyingReplacements = true
                
                var updatedText = self.bodyText
                var hasChanges = false
                
                // Apply replacements from end to start to preserve positions
                // Process in reverse order to maintain string indices
                for replacement in result.replacements.reversed() {
                    // Skip if replacement text is already the same as original (case-insensitive)
                    let originalTrimmed = replacement.originalText.trimmed()
                    let replacementTrimmed = replacement.replacement.trimmed()
                    
                    if originalTrimmed.lowercased() == replacementTrimmed.lowercased() {
                        continue
                    }
                    
                    // Only replace if the original text still exists in the current text
                    // (case-insensitive, whole word match)
                    let escaped = NSRegularExpression.escapedPattern(for: replacement.originalText)
                    let pattern = "\\b\(escaped)\\b"

                    do {
                        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                        let range = NSRange(updatedText.startIndex..., in: updatedText)
                        let matches = regex.matches(in: updatedText, options: [], range: range)

                        if !matches.isEmpty {
                            // Replace from end to start to preserve indices
                            for match in matches.reversed() {
                                if let matchRange = Range(match.range, in: updatedText) {
                                    let matchedText = String(updatedText[matchRange])
                                    let matchedTrimmed = matchedText.trimmed()

                                    // CRITICAL: Only replace if it's not already the replacement
                                    // text (case-insensitive). This prevents replacing "Sarah Z."
                                    // with "Sarah Z." which would cause period repetition
                                    if matchedTrimmed.lowercased()
                                        != replacementTrimmed.lowercased() {
                                        updatedText.replaceSubrange(matchRange, with: replacement.replacement)
                                        hasChanges = true
                                    }
                                }
                            }
                        }
                    } catch {
                        Self.logger.warning("Invalid regex pattern '\(pattern)': \(error)")
                        // Continue to next replacement
                        continue
                    }
                }
                
                // Only update if text actually changed
                if hasChanges {
                    // Store the updated text to check against in next analysis
                    // REMOVED: unused previousText
                    self.lastReplacementText = updatedText
                    
                    adaptiveWithAnimation {
                        self.bodyText = updatedText
                    }

                    // Reset flag after a delay to allow onChange to complete
                    Task { [weak self] in
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                        } catch {
                            // Task was cancelled, ignored
                        }
                        self?.isApplyingReplacements = false
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
        }
    }
    
    func saveNote(viewContext: NSManagedObjectContext) {
        let trimmed = bodyText.trimmed()
        guard !trimmed.isEmpty else { return }
        
        let scope: NoteScope
        if selectedStudentIDs.count == 1, let firstID = selectedStudentIDs.first {
            scope = .student(firstID)
        } else if selectedStudentIDs.count > 1 {
            scope = .students(selectedStudentIDs.sorted { $0.uuidString < $1.uuidString })
        } else {
            scope = .all
        }
        
        // Fetch CDStudentTrackEnrollmentEntity if selectedEnrollmentID is set
        var studentTrackEnrollment: CDStudentTrackEnrollmentEntity?
        if let enrollmentID = selectedEnrollmentID {
            let descriptor = NSFetchRequest<CDStudentTrackEnrollmentEntity>(entityName: "StudentTrackEnrollment")
            descriptor.predicate = NSPredicate(format: "id == %@", enrollmentID as CVarArg)
            studentTrackEnrollment = viewContext.safeFetchFirst(descriptor)
        }

        // Fetch CDLesson if selectedLessonID is set
        var lesson: CDLesson?
        if let lessonID = selectedLessonID {
            let descriptor = NSFetchRequest<CDLesson>(entityName: "Lesson")
            descriptor.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
            lesson = viewContext.safeFetchFirst(descriptor)
        }

        let newNote = CDNote(context: viewContext)
        newNote.createdAt = noteDate
        newNote.body = trimmed
        newNote.scope = scope
        newNote.tags = tags as NSArray
        newNote.includeInReport = includeInReport
        newNote.needsFollowUp = needsFollowUp
        newNote.lesson = lesson
        newNote.studentTrackEnrollment = studentTrackEnrollment
        newNote.imagePath = attachedImagePath
        ToastService.shared.show("Note saved", type: .success, duration: 1.5)
    }

    func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let uiImage = PlatformImage(data: data) {
                    await MainActor.run { processImage(uiImage) }
                }
            } catch {
                Self.logger.warning("Failed to load photo: \(error)")
            }
        }
    }
    
    func processImage(_ image: PlatformImage) {
        self.attachedImage = image
        do {
            self.attachedImagePath = try PhotoStorageService.saveImage(image)
        } catch {
            Self.logger.error("Failed to save image: \(error)")
        }
    }
    
    func getDisplayName(for student: CDStudent, students: [CDStudent]) -> String {
        // If there are other students in the full roster with the same first name, use Last Initial
        let duplicateCount = students.filter { $0.firstName.lowercased() == student.firstName.lowercased() }.count
        if duplicateCount > 1 {
            let lastInitial = student.lastName.first.map { String($0) } ?? ""
            return "\(student.firstName) \(lastInitial)."
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
                self.aiError = "Apple Intelligence is not available on this device."
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
            } catch let error as LanguageModelSession.GenerationError {
                self.aiError = Self.userMessage(for: error)
                self.isProcessingAI = false
            } catch {
                self.aiError = error.localizedDescription
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
    static func userMessage(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable:
            return "Apple Intelligence model is not available. It may be downloading — please try again later."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .exceededContextWindowSize:
            return "The text is too long for on-device processing. Try with a shorter note."
        case .unsupportedLanguageOrLocale:
            return "This language is not supported by Apple Intelligence."
        case .refusal:
            return "The request could not be processed due to content restrictions."
        case .concurrentRequests:
            return "Another AI request is already in progress. Please wait."
        default:
            return error.localizedDescription
        }
    }
    #endif
    #endif
}
