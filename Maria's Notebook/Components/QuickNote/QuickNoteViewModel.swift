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
    
    // MARK: - Dependencies
    private let tagger = StudentTagger()
    let initialStudentID: UUID?
    
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
        let studentData = getStudentData(from: students)
        Task {
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
            
            // Suggest fuzzy matches that are not already selected
            self.detectedCandidateIDs = result.fuzzy.subtracting(self.selectedStudentIDs)
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
        
        let newNote = Note(
            createdAt: noteDate,
            body: trimmed,
            scope: scope,
            category: category,
            includeInReport: includeInReport,
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
            print("Failed to save image: \(error)")
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

