import SwiftUI
import SwiftData

// MARK: - Main View
struct AppleIntelligenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var students: [Student] 
    
    let notes: [Note]
    
    // Editor State
    @State private var editorText: String = ""
    @State private var isAnonymized: Bool = false
    @FocusState private var isFocused: Bool
    @State private var aiTriggerCounter: Int = 0
    
    // UI State
    @State private var currentTemplate: PromptTemplate? = nil
    
    init(notes: [Note]) {
        self.notes = notes
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Control Bar
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
                                Button { applyTemplate(template) } label: { Label(template.rawValue, systemImage: template.icon) }
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
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Material.bar)
                
                Divider()
                
                // 2. Editor with Magic Button
                ZStack(alignment: .bottomTrailing) {
                    if editorText.isEmpty {
                        ContentUnavailableView("Processing Data...", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        // Use the SmartTextEditor from UnifiedNoteEditor.swift
                        SmartTextEditor(text: $editorText, triggerTool: $aiTriggerCounter)
                            .padding()
                            .background(editorBackgroundColor)
                    }
                    
                    // Floating "Sparkles" Action Button
                    if #available(iOS 18.0, macOS 15.0, *) {
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        }
    }
    
    // MARK: - Logic Helpers
    
    private func regenerateContent() {
        let formatter = SmartNoteFormatter(students: students, anonymize: isAnonymized)
        let rawContext = formatter.generateContext(from: notes)
        
        if let template = currentTemplate, template != .raw {
            editorText = template.instruction + "\n\n" + rawContext
        } else {
            editorText = rawContext
            currentTemplate = .raw
        }
    }
    
    private func applyTemplate(_ template: PromptTemplate) {
        currentTemplate = template
        regenerateContent()
        // Delay slightly to allow text to update, then invoke tools
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            aiTriggerCounter += 1
        }
    }
    
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
    let students: [Student]
    let anonymize: Bool
    
    func generateContext(from notes: [Note]) -> String {
        let sortedNotes = notes.sorted { $0.updatedAt < $1.updatedAt }
        let header = """
        [DATA EXPORT START]
        Scope: \(sortedNotes.count) Note(s)
        Timeline: \(dateRangeString(notes: sortedNotes))
        ----------------------------------------
        
        """
        let body = sortedNotes.map { formatSingleNote($0) }.joined(separator: "\n\n")
        return header + body + "\n\n[DATA EXPORT END]"
    }
    
    private func formatSingleNote(_ note: Note) -> String {
        let studentName = resolveStudentName(for: note.scope)
        let contextDetail = resolveContextDetail(for: note)
        let dateStr = note.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let category = note.category.rawValue.capitalized
        
        return """
        ENTRY: \(dateStr)
        STUDENT: \(studentName)
        CONTEXT: \(contextDetail) (\(category))
        NOTE:
        \(note.body)
        """
    }
    
    private func resolveStudentName(for scope: NoteScope) -> String {
        switch scope {
        case .all: return "General / Class-wide"
        case .student(let id):
            guard let student = students.first(where: { $0.id == id }) else { return "Unknown Student" }
            return anonymize ? "Student \(student.firstName.prefix(1))" : "\(student.firstName) \(student.lastName)"
        case .students(let ids):
            if anonymize { return "Group of \(ids.count) Students" }
            let names = ids.compactMap { id in students.first(where: { $0.id == id })?.firstName }
            return names.joined(separator: ", ")
        }
    }
    
    private func resolveContextDetail(for note: Note) -> String {
        if let lesson = note.lesson { return "Lesson: \(lesson.name)" }
        if let work = note.work { return "Work: \(work.title)" }
        if let sl = note.studentLesson, let l = sl.lesson { return "Presentation: \(l.name)" }
        if let pres = note.presentation {
            let title = (pres.lessonTitleSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Presentation" : "Presentation: \(title)"
        }
        return "General Observation"
    }
    
    private func dateRangeString(notes: [Note]) -> String {
        guard let first = notes.first?.updatedAt, let last = notes.last?.updatedAt else { return "N/A" }
        if Calendar.current.isDate(first, inSameDayAs: last) { return first.formatted(date: .abbreviated, time: .omitted) }
        return "\(first.formatted(date: .numeric, time: .omitted)) - \(last.formatted(date: .numeric, time: .omitted))"
    }
}

// MARK: - Prompt Templates
enum PromptTemplate: String, CaseIterable {
    case raw = "Raw Data"
    case parentEmail = "Parent Email"
    case reportCard = "Report Card"
    case actionPlan = "Action Plan"
    
    var icon: String {
        switch self {
        case .raw: return "doc.text"
        case .parentEmail: return "envelope.fill"
        case .reportCard: return "list.clipboard.fill"
        case .actionPlan: return "checklist"
        }
    }
    
    var instruction: String {
        switch self {
        case .raw: return ""
        case .parentEmail: return "INSTRUCTION: Draft a supportive, professional email to the parents summarizing the progress shown below. Highlight achievements and 1 area for growth."
        case .reportCard: return "INSTRUCTION: Summarize the following observations into a formal paragraph for a semester report card."
        case .actionPlan: return "INSTRUCTION: Analyze the observations below and list 3 specific follow-up actions."
        }
    }
}

