import SwiftUI
import SwiftData
import PhotosUI
import Combine

// Conditional Import for Apple Intelligence features
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
class QuickNoteViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Content
    @Published var bodyText: String = ""
    @Published var category: NoteCategory = .general
    @Published var selectedStudentIDs: Set<UUID> = []
    @Published var includeInReport: Bool = false
    @Published var noteDate: Date = Date()
    
    // Attachments
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    @Published var attachedImage: PlatformImage? = nil
    @Published var attachedImagePath: String? = nil
    
    // AI & Analysis State
    @Published var detectedCandidateIDs: Set<UUID> = []
    @Published var isProcessingAI: Bool = false
    @Published var aiError: String? = nil
    
    // UI State
    @Published var isShowingStudentPicker: Bool = false
    @Published var isShowingCamera: Bool = false
    
    // Track Context
    @Published var selectedEnrollmentID: UUID? = nil
    
    // MARK: - Dependencies
    private let tagger = StudentTagger()
    let initialStudentID: UUID?
    
    // MARK: - Debouncing
    private var analysisTask: Task<Void, Never>? = nil
    private var isApplyingReplacements: Bool = false
    private var lastReplacementText: String? = nil
    
    // MARK: - Initialization
    
    init(initialStudentID: UUID? = nil) {
        self.initialStudentID = initialStudentID
        
        if let initialID = initialStudentID {
            self.selectedStudentIDs.insert(initialID)
        }
    }
    
    // MARK: - Public Methods
    
    func setupInitialState() {
        if let initialID = initialStudentID {
            selectedStudentIDs.insert(initialID)
        }
    }
    
    func analyzeText(_ text: String, students: [Student]) {
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
            try? await Task.sleep(for: .milliseconds(300))
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            let studentData = getStudentData(from: students)
            let result = await tagger.findStudentMatches(in: text, studentData: studentData)
            
            // Auto-add exact matches that are not already selected
            let newExacts = result.exact.subtracting(self.selectedStudentIDs)
            if !newExacts.isEmpty {
                withAnimation {
                    self.selectedStudentIDs.formUnion(newExacts)
                }
            }
            
            // Auto-select unique matches (autoSelect set from enhanced detection)
            let newAutoSelects = result.autoSelect.subtracting(self.selectedStudentIDs)
            if !newAutoSelects.isEmpty {
                withAnimation {
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
                    let originalTrimmed = replacement.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let replacementTrimmed = replacement.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if originalTrimmed.lowercased() == replacementTrimmed.lowercased() {
                        continue
                    }
                    
                    // Only replace if the original text still exists in the current text
                    // (case-insensitive, whole word match)
                    let escaped = NSRegularExpression.escapedPattern(for: replacement.originalText)
                    let pattern = "\\b\(escaped)\\b"
                    
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let range = NSRange(updatedText.startIndex..., in: updatedText)
                        let matches = regex.matches(in: updatedText, options: [], range: range)
                        
                        if !matches.isEmpty {
                            // Replace from end to start to preserve indices
                            for match in matches.reversed() {
                                if let matchRange = Range(match.range, in: updatedText) {
                                    let matchedText = String(updatedText[matchRange])
                                    let matchedTrimmed = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // CRITICAL: Only replace if it's not already the replacement text (case-insensitive)
                                    // This prevents replacing "Sarah Z." with "Sarah Z." which would cause period repetition
                                    if matchedTrimmed.lowercased() != replacementTrimmed.lowercased() {
                                        updatedText.replaceSubrange(matchRange, with: replacement.replacement)
                                        hasChanges = true
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Only update if text actually changed
                if hasChanges {
                    // Store the updated text to check against in next analysis
                    // REMOVED: unused previousText
                    self.lastReplacementText = updatedText
                    
                    withAnimation {
                        self.bodyText = updatedText
                    }
                    
                    // Reset flag after a delay to allow onChange to complete
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        self.isApplyingReplacements = false
                    }
                } else {
                    // No changes, reset flag immediately
                    self.isApplyingReplacements = false
                }
            }
        }
    }
    
    func formatNamesLocally(students: [Student]) {
        guard !bodyText.isEmpty else { return }
        isProcessingAI = true // Show spinner
        
        let studentData = getStudentData(from: students)
        Task {
            // Use the actor to perform robust string replacement
            let newText = await tagger.formatStudentNames(in: bodyText, studentData: studentData)
            
            withAnimation {
                self.bodyText = newText
                self.isProcessingAI = false
            }
        }
    }
    
    func saveNote(modelContext: ModelContext) {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let scope: NoteScope
        if selectedStudentIDs.count == 1 {
            scope = .student(selectedStudentIDs.first!)
        } else if selectedStudentIDs.count > 1 {
            scope = .students(selectedStudentIDs.sorted { $0.uuidString < $1.uuidString })
        } else {
            scope = .all
        }
        
        // Fetch StudentTrackEnrollment if selectedEnrollmentID is set
        var studentTrackEnrollment: StudentTrackEnrollment? = nil
        if let enrollmentID = selectedEnrollmentID {
            let descriptor = FetchDescriptor<StudentTrackEnrollment>(
                predicate: #Predicate<StudentTrackEnrollment> { $0.id == enrollmentID }
            )
            studentTrackEnrollment = modelContext.safeFetchFirst(descriptor)
        }
        
        let newNote = Note(
            createdAt: noteDate,
            body: trimmed,
            scope: scope,
            category: category,
            includeInReport: includeInReport,
            studentTrackEnrollment: studentTrackEnrollment,
            imagePath: attachedImagePath
        )
        
        modelContext.insert(newNote)
    }
    
    func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = PlatformImage(data: data) {
                await MainActor.run { processImage(uiImage) }
            }
        }
    }
    
    func processImage(_ image: PlatformImage) {
        self.attachedImage = image
        do {
            self.attachedImagePath = try PhotoStorageService.saveImage(image)
        } catch {
            #if DEBUG
            print("Failed to save image: \(error)")
            #endif
        }
    }
    
    func getDisplayName(for student: Student, students: [Student]) -> String {
        // If there are other students in the full roster with the same first name, use Last Initial
        let duplicateCount = students.filter { $0.firstName.lowercased() == student.firstName.lowercased() }.count
        if duplicateCount > 1 {
            let lastInitial = student.lastName.first.map { String($0) } ?? ""
            return "\(student.firstName) \(lastInitial)."
        }
        return student.firstName
    }
    
    func categoryColor(_ cat: NoteCategory) -> Color {
        switch cat {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .green
        case .attendance: return .teal
        case .general: return .gray
        }
    }
    
    // MARK: - Private Methods
    
    private func getStudentData(from students: [Student]) -> [StudentData] {
        return students.map { student in
            StudentData(
                id: student.id,
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
        
        let lastChar = text.last!
        return lastChar.isWhitespace || lastChar.isPunctuation
    }
    
    // MARK: - Apple Intelligence
    
    #if ENABLE_FOUNDATION_MODELS
    func runAI(instruction: String) {
        guard !bodyText.isEmpty else { return }
        isProcessingAI = true
        
        Task {
            await processAIRequest(instruction: instruction)
        }
    }
    
    private func processAIRequest(instruction: String) async {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 18.0, *) {
            do {
                let session = LanguageModelSession()
                let prompt = AIPrompts.processQuickNote(instruction: instruction, text: bodyText)
                let response = try await session.respond(to: prompt)
                
                withAnimation {
                    self.bodyText = response.content
                    self.isProcessingAI = false
                }
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
    #endif
}

