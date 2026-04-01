import SwiftUI
import CoreData

// Only import if the flag is enabled (see ENABLE_FOUNDATION_MODELS.md)
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Main View
struct AppleIntelligenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: []) private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    let notes: [CDNote]
    
    // Editor State
    @State private var editorText: String = ""
    @State private var isAnonymized: Bool = false
    @FocusState private var isFocused: Bool
    @State private var aiTriggerCounter: Int = 0
    @State private var pendingAITrigger: Bool = false
    
    // AI State
    @State private var isGenerating: Bool = false
    @State private var generationError: String?

    // UI State
    @State private var currentTemplate: PromptTemplate?
    
    init(notes: [CDNote]) {
        self.notes = notes
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Control Bar
                controlBar
                
                Divider()
                
                // 2. Editor Area
                ZStack(alignment: .bottomTrailing) {
                    if editorText.isEmpty && !isGenerating {
                        ContentUnavailableView("Processing Data...", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        // Main Editor
                        SmartTextEditor(text: $editorText, triggerTool: $aiTriggerCounter)
                            .padding()
                            .background(editorBackgroundColor)
                            .disabled(isGenerating) // Lock input while generating
                            .opacity(isGenerating ? 0.6 : 1.0)
                    }
                    
                    // Loading Indicator or Magic Button
                    if isGenerating {
                        ProgressView("Drafting...")
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(12)
                            .padding()
                    } else if #available(iOS 18.0, macOS 15.0, *) {
                         // System Writing Tools Trigger (Fallback or Polish)
                         Button {
                             aiTriggerCounter += 1
                         } label: {
                             Image(systemName: "sparkles")
                                 .font(.title2)
                                 .foregroundStyle(.white)
                                 .frame(width: 50, height: 50)
                                 .background(Color.purple)
                                 .clipShape(Circle())
                                 .shadow(radius: 4)
                         }
                         .padding()
                    }
                }
            }
            .navigationTitle("AI Assistant")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: editorText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                regenerateContent()
            }
            .onChange(of: editorText) { _, newText in
                // Trigger AI tools after text is set and view is ready
                if pendingAITrigger && !newText.isEmpty {
                    pendingAITrigger = false
                    // onChange fires after the view has updated, so we can trigger immediately
                    aiTriggerCounter += 1
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var controlBar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isAnonymized) {
                Label("Anonymize", systemImage: isAnonymized ? "eye.slash.fill" : "eye.fill")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .toggleStyle(.button)
            .tint(.secondary)
            .onChange(of: isAnonymized) { _, _ in regenerateContent() }
            
            Spacer()
            
            Menu {
                Section("Context Generators") {
                    Button { applyTemplate(.raw) } label: { Label("Raw Data Context", systemImage: "doc.text") }
                }
                Section("AI Instructions") {
                    ForEach(PromptTemplate.allCases.filter { $0 != .raw }, id: \.self) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            Label(template.rawValue, systemImage: template.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentTemplate?.rawValue ?? "Select Template")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(UIConstants.OpacityConstants.light))
                .clipShape(Capsule())
                .foregroundStyle(Color.accentColor)
            }
            .disabled(isGenerating)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Material.bar)
    }
    
    // MARK: - Logic Helpers
    
    private func regenerateContent() {
        let formatter = SmartNoteFormatter(students: students, anonymize: isAnonymized)
        let rawContext = formatter.generateContext(from: notes)
        
        // Reset to raw data if we aren't using a template or just toggled anonymization
        if currentTemplate == nil || currentTemplate == .raw {
            editorText = rawContext
            currentTemplate = .raw
        } else {
            // If we have a template active, re-apply it (re-generate) with new settings
            if let template = currentTemplate {
                applyTemplate(template)
            }
        }
    }
    
    private func applyTemplate(_ template: PromptTemplate) {
        currentTemplate = template
        let formatter = SmartNoteFormatter(students: students, anonymize: isAnonymized)
        let rawContext = formatter.generateContext(from: notes)
        
        if template == .raw {
            editorText = rawContext
            return
        }

        // Logic split: Use FoundationModels if available, otherwise fallback to system tools text prep
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        Task {
            await generateWithFoundationModel(template: template, context: rawContext)
        }
        #else
        // Fallback: Prepend instructions and trigger system tools
        pendingAITrigger = true
        editorText = template.instruction + "\n\n" + rawContext
        #endif
    }
    
    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @MainActor
    private func generateWithFoundationModel(template: PromptTemplate, context: String) async {
        isGenerating = true
        generationError = nil
        
        guard SystemLanguageModel.default.isAvailable else {
            generationError = unavailabilityMessage()
            editorText = context
            isGenerating = false
            return
        }
        
        // Set up the session with specific persona based on template
        let session = LanguageModelSession(instructions: AIPrompts.advancedAssistant)
        
        do {
            let prompt = """
            \(template.instruction)
            
            DATA:
            \(context)
            """
            
            // Generate unstructured text
            let response = try await session.respond(to: prompt, options: .init(temperature: 0.7))
            
            // Animate the text in (simple replacement for now)
            adaptiveWithAnimation {
                editorText = response.content
            }
        } catch let error as LanguageModelSession.GenerationError {
            let message = userMessage(for: error)
            generationError = message
            editorText = context + "\n\n[Error: \(message)]"
        } catch {
            generationError = error.localizedDescription
            editorText = context + "\n\n[Error generating draft: \(error.localizedDescription)]"
        }
        
        isGenerating = false
    }
    
    private func unavailabilityMessage() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Please enable Apple Intelligence in Settings to use this feature."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading. Please try again later."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }
    
    private func userMessage(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable:
            return "Apple Intelligence model is not available. It may be downloading — please try again later."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .exceededContextWindowSize:
            return "The data is too large for on-device processing. Try selecting fewer notes."
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
    
    private var editorBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

// MARK: - Smart Formatter
struct SmartNoteFormatter {
    let students: [CDStudent]
    let anonymize: Bool
    
    func generateContext(from notes: [CDNote]) -> String {
        let sortedNotes = notes.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        let header = """
        [DATA EXPORT START]
        Scope: \(sortedNotes.count) CDNote(s)
        Timeline: \(dateRangeString(notes: sortedNotes))
        ----------------------------------------
        
        """
        let body = sortedNotes.map { formatSingleNote($0) }.joined(separator: "\n\n")
        return header + body + "\n\n[DATA EXPORT END]"
    }
    
    private func formatSingleNote(_ note: CDNote) -> String {
        let studentName = resolveStudentName(for: note.scope)
        let contextDetail = resolveContextDetail(for: note)
        let dateStr = (note.updatedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)
        let tagNames = ((note.tags as? [String]) ?? []).map { TagHelper.tagName($0) }.joined(separator: ", ")
        let tagLabel = tagNames.isEmpty ? "General" : tagNames
        
        return """
        ENTRY: \(dateStr)
        STUDENT: \(studentName)
        CONTEXT: \(contextDetail) (\(tagLabel))
        NOTE:
        \(note.body)
        """
    }
    
    private func resolveStudentName(for scope: NoteScope) -> String {
        switch scope {
        case .all: return "General / Class-wide"
        case .student(let id):
            guard let student = students.first(where: { $0.id == id }) else { return "Unknown CDStudent" }
            return anonymize ? "CDStudent \(student.firstName.prefix(1))" : "\(student.firstName) \(student.lastName)"
        case .students(let ids):
            if anonymize { return "Group of \(ids.count) Students" }
            let names = ids.compactMap { id in students.first(where: { $0.id == id })?.firstName }
            return names.joined(separator: ", ")
        }
    }
    
    private func resolveContextDetail(for note: CDNote) -> String {
        if let lesson = note.lesson { return "CDLesson: \(lesson.name)" }
        if let work = note.work { return "Work: \(work.title)" }
        if let pres = note.lessonAssignment {
            let title = (pres.lessonTitleSnapshot ?? "").trimmed()
            return title.isEmpty ? "Presentation" : "CDPresentation: \(title)"
        }
        return "General Observation"
    }
    
    private func dateRangeString(notes: [CDNote]) -> String {
        guard let first = notes.first?.updatedAt ?? notes.first?.createdAt, let last = notes.last?.updatedAt ?? notes.last?.createdAt else { return "N/A" }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(first.formatted(date: .numeric, time: .omitted)) - \(last.formatted(date: .numeric, time: .omitted))"
    }
}

// MARK: - Prompt Templates
enum PromptTemplate: String, CaseIterable {
    case raw = "Raw Data"
    case parentEmail = "Parent Email"
    case reportCard = "Report Card"
    case actionPlan = "Action Plan"
    case summary = "Weekly Summary"
    
    var icon: String {
        switch self {
        case .raw: return "doc.text"
        case .parentEmail: return "envelope.fill"
        case .reportCard: return "list.clipboard.fill"
        case .actionPlan: return "checklist"
        case .summary: return "text.alignleft"
        }
    }
    
    // swiftlint:disable line_length
    var instruction: String {
        switch self {
        case .raw: return ""
        case .parentEmail:
            return "Task: Draft a supportive, professional email to the parents. Summarize the progress shown in the data. Highlight achievements and gently mention 1 area for growth if applicable."
        case .reportCard:
            return "Task: Summarize the observations into a formal paragraph suitable for a semester report card. Focus on observed behaviors and academic progress."
        case .actionPlan:
            return "Task: Analyze the observations and list 3 specific, actionable follow-up steps for the teacher. Format as a checklist."
        case .summary:
            return "Task: Provide a concise bulleted summary of the key themes found in these notes."
        }
    }
    // swiftlint:enable line_length
}
