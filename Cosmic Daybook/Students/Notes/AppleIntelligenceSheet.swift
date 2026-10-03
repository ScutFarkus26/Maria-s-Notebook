import SwiftUI
import CoreData

// Only import if the flag is enabled (see ENABLE_FOUNDATION_MODELS.md)
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Main View
struct AppleIntelligenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    // Test student filtering
    @TestStudentVisibility private var testStudents

    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.enrolled,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        )
    }

    let notes: [CDNote]
    
    // Editor State
    // editorText is internal so the FoundationModels generation extension
    // (AppleIntelligenceSheet+Generation.swift) can drive it.
    @State var editorText: String = ""
    @State private var isAnonymized: Bool = false
    @State private var aiTriggerCounter: Int = 0
    @State private var pendingAITrigger: Bool = false

    // AI State (internal: see AppleIntelligenceSheet+Generation.swift)
    @State var isGenerating: Bool = false
    @State var generationError: String?

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

                if let generationError {
                    errorBanner(generationError)
                }
                
                // 2. Editor Area
                ZStack(alignment: .bottomTrailing) {
                    if editorText.isEmpty && !isGenerating {
                        ContentUnavailableView("Gathering notes…", systemImage: "arrow.triangle.2.circlepath")
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
                        ProgressView("Drafting…")
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
            .navigationTitle("Writing Help")
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
                Section("Start From") {
                    Button { applyTemplate(.raw) } label: { Label("Notes Only", systemImage: "doc.text") }
                }
                Section("Drafts") {
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
                    Text(currentTemplate?.rawValue ?? "Choose a Draft")
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
    
    /// A failed draft is reported here, never written into the note text.
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                generationError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(UIConstants.OpacityConstants.light))
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
        generationError = nil
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
    
    // FoundationModels draft generation lives in AppleIntelligenceSheet+Generation.swift.

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
    
    /// The notes as plain text: a one-line header ("3 notes, Sep 2 – Sep 30")
    /// and each note under plain labels. The guide reads and shares this, and
    /// it is also what Apple Intelligence drafts from.
    func generateContext(from notes: [CDNote]) -> String {
        let sortedNotes = notes.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        let body = sortedNotes.map { formatSingleNote($0) }.joined(separator: "\n\n")
        return header(for: sortedNotes) + "\n\n" + body
    }

    func header(for sortedNotes: [CDNote]) -> String {
        let count = sortedNotes.count
        let counted = "\(count) \(count == 1 ? "note" : "notes")"
        guard let dates = dateRangeString(notes: sortedNotes) else { return counted }
        return counted + ", " + dates
    }
    
    private func formatSingleNote(_ note: CDNote) -> String {
        let studentName = resolveStudentName(for: note.scope)
        let contextDetail = resolveContextDetail(for: note)
        let dateStr = (note.updatedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)
        let tagNames = ((note.tags as? [String]) ?? []).map { TagHelper.tagName($0) }.joined(separator: ", ")
        let about = tagNames.isEmpty ? contextDetail : "\(contextDetail) (\(tagNames))"

        return """
        Date: \(dateStr)
        Student: \(studentName)
        About: \(about)
        Note: \(note.body)
        """
    }
    
    private func resolveStudentName(for scope: NoteScope) -> String {
        switch scope {
        case .all: return "Whole class"
        case .student(let id):
            guard let student = students.first(where: { $0.id == id }) else { return "Student removed" }
            return anonymize ? "Student \(student.firstName.prefix(1))" : student.fullName
        case .students(let ids):
            if anonymize { return "Group of \(ids.count) \(ids.count == 1 ? "student" : "students")" }
            let names = ids.compactMap { id in students.first(where: { $0.id == id })?.firstName }
            return names.joined(separator: ", ")
        }
    }
    
    private func resolveContextDetail(for note: CDNote) -> String {
        if let lesson = note.lesson { return "\(lesson.name) (lesson)" }
        if let work = note.work { return "\(work.title) (work)" }
        if let pres = note.lessonAssignment {
            let title = (pres.lessonTitleSnapshot ?? "").trimmed()
            return title.isEmpty ? "A presentation" : "\(title) (presentation)"
        }
        return "General observation"
    }
    
    private func dateRangeString(notes: [CDNote]) -> String? {
        guard let first = notes.first?.updatedAt ?? notes.first?.createdAt,
              let last = notes.last?.updatedAt ?? notes.last?.createdAt else { return nil }
        if AppCalendar.isSameDay(first, last) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        let from = first.formatted(date: .abbreviated, time: .omitted)
        let through = last.formatted(date: .abbreviated, time: .omitted)
        return "\(from) – \(through)"
    }
}

// MARK: - Prompt Templates
enum PromptTemplate: String, CaseIterable {
    case raw = "Notes Only"
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
