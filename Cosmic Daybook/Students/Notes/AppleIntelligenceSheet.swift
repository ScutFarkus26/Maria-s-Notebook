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

    /// Every child the notes might name, withdrawn ones included, so their
    /// names resolve in the text and Anonymize hides them too.
    private var students: [CDStudent] { dependencies.roster.all }

    let notes: [CDNote]

    // Editor State
    // editorText is internal so the FoundationModels generation extension
    // (AppleIntelligenceSheet+Generation.swift) can drive it.
    @State var editorText: String = ""
    /// What the sheet itself last put in the editor. When the editor holds
    /// anything else she has edited it, and replacing it asks first.
    @State var generatedText: String = ""
    @State private var isAnonymized: Bool = false
    @State private var aiTriggerCounter: Int = 0
    @State private var pendingAITrigger: Bool = false
    @State private var pendingReplacement: Replacement?

    /// A change that rewrites the editor's text.
    private enum Replacement: Equatable {
        case anonymize(Bool)
        case template(PromptTemplate)
    }

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
                    if notes.isEmpty {
                        ContentUnavailableView(
                            "No Notes This School Year",
                            systemImage: "note.text",
                            description: Text("Notes about this child from this school year show here to draft from.")
                        )
                    } else if editorText.isEmpty && !isGenerating {
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
            .confirmationDialog(
                "Replace your edits?",
                isPresented: Binding(
                    get: { pendingReplacement != nil },
                    set: { if !$0 { pendingReplacement = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    if let change = pendingReplacement { apply(change) }
                    pendingReplacement = nil
                }
                Button("Keep My Text", role: .cancel) { pendingReplacement = nil }
            } message: {
                Text("You changed the text here. This writes it over with a new draft.")
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
            Toggle(isOn: Binding(
                get: { isAnonymized },
                set: { request(.anonymize($0)) }
            )) {
                Label("Anonymize", systemImage: isAnonymized ? "eye.slash.fill" : "eye.fill")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .toggleStyle(.button)
            .tint(.secondary)
            .disabled(notes.isEmpty)

            Spacer()

            Menu {
                Section("Start From") {
                    Button { request(.template(.raw)) } label: { Label("Notes Only", systemImage: "doc.text") }
                }
                Section("Drafts") {
                    ForEach(PromptTemplate.allCases.filter { $0 != .raw }, id: \.self) { template in
                        Button {
                            request(.template(template))
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
            .disabled(isGenerating || notes.isEmpty)
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

    /// Runs a change that rewrites the text, asking first when she has edited
    /// it: toggling Anonymize or picking a draft used to write over her edits.
    private func request(_ change: Replacement) {
        if editorText != generatedText {
            pendingReplacement = change
        } else {
            apply(change)
        }
    }

    private func apply(_ change: Replacement) {
        switch change {
        case .anonymize(let anonymize):
            isAnonymized = anonymize
            regenerateContent()
        case .template(let template):
            applyTemplate(template)
        }
    }

    /// Puts text the sheet made into the editor.
    func show(_ text: String) {
        generatedText = text
        editorText = text
    }

    private func regenerateContent() {
        guard !notes.isEmpty else { return }
        let formatter = SmartNoteFormatter(students: students, anonymize: isAnonymized)
        let rawContext = formatter.generateContext(from: notes)

        // Reset to raw data if we aren't using a template or just toggled anonymization
        if currentTemplate == nil || currentTemplate == .raw {
            show(rawContext)
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
            show(rawContext)
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
        show(template.instruction + "\n\n" + rawContext)
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
