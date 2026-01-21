import SwiftUI
import SwiftData
import PhotosUI

// MARK: - QuickNoteSheet
struct QuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Data
    @Query(sort: [Foundation.SortDescriptor(\Student.firstName), Foundation.SortDescriptor(\Student.lastName)])
    private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var students: [Student] { studentsRaw.uniqueByID }

    // MARK: - View Model
    @StateObject private var viewModel: QuickNoteViewModel
    
    // MARK: - UI State
    @FocusState private var isFocused: Bool
    
    // MARK: - Init
    init(initialStudentID: UUID? = nil) {
        _viewModel = StateObject(wrappedValue: QuickNoteViewModel(initialStudentID: initialStudentID))
    }
    
    // MARK: - Body
    var body: some View {
        actualView
            .onAppear {
                // Update view model with students once available
                // Note: ViewModel holds students for display name logic
                viewModel.setupInitialState()
                
                // Delay focus to allow animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
    }
    
    private var actualView: some View {
        #if os(macOS)
        macOSLayout
            .frame(minWidth: 650, minHeight: 550)
        #else
        iOSLayout
        #endif
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                Text("New Note")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                
                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    
                    Spacer()
                    
                    Button("Save") { 
                        viewModel.saveNote(modelContext: modelContext)
                        dismiss()
                    }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            HStack(spacing: 0) {
                // Sidebar Metadata
                VStack(alignment: .leading, spacing: 20) {
                    // Date Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Date", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $viewModel.noteDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact)
                    }
                    
                    // Category Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Category", systemImage: "tag")
                            .font(.caption).foregroundStyle(.secondary)
                        QuickNoteCategoryMenu(
                            category: $viewModel.category,
                            categoryColor: viewModel.categoryColor
                        )
                    }
                    
                    // Flags
                    Toggle(isOn: $viewModel.includeInReport) {
                        Label("Flag for Report", systemImage: "flag")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Spacer()
                }
                .padding()
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // Editor Area
                VStack(spacing: 0) {
                    // Selected Students
                    if !viewModel.selectedStudentIDs.isEmpty {
                        SelectedStudentsBar(
                            students: students,
                            selectedStudentIDs: viewModel.selectedStudentIDs,
                            displayName: { viewModel.getDisplayName(for: $0, students: students) },
                            onRemove: { id in
                                withAnimation {
                                    _ = viewModel.selectedStudentIDs.remove(id)
                                }
                            }
                        )
                    }
                    
                    // Editor
                    QuickNoteEditor(
                        bodyText: $viewModel.bodyText,
                        isFocused: $isFocused,
                        isProcessingAI: viewModel.isProcessingAI,
                        onTextChange: { viewModel.analyzeText($0, students: students) }
                    )
                    
                    // Suggestions Bar
                    if !viewModel.detectedCandidateIDs.isEmpty {
                        SuggestionsBar(
                            students: students,
                            detectedCandidateIDs: viewModel.detectedCandidateIDs,
                            displayName: { viewModel.getDisplayName(for: $0, students: students) },
                            onAdd: { id in
                                withAnimation {
                                    _ = viewModel.selectedStudentIDs.insert(id)
                                    _ = viewModel.detectedCandidateIDs.remove(id)
                                }
                            }
                        )
                    }
                    
                    // Toolbar
                    HStack {
                        Button { viewModel.isShowingStudentPicker = true } label: {
                            Label("Add Student", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $viewModel.isShowingStudentPicker) {
                            StudentPickerPopover(
                                students: students,
                                selectedIDs: $viewModel.selectedStudentIDs,
                                onDone: { viewModel.isShowingStudentPicker = false }
                            )
                        }
                        
                        Spacer()
                        
                        // Apple Intelligence / Magic Menu
                        aiMenuButton(students: students)
                        
                        // Attachments
                        if let img = viewModel.attachedImage {
                            QuickNoteAttachmentThumbnail(image: img) {
                                viewModel.attachedImage = nil
                                viewModel.attachedImagePath = nil
                            }
                        }
                        
                        PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in viewModel.loadPhoto(newItem) }
        .alert("AI Error", isPresented: Binding(
            get: { viewModel.aiError != nil },
            set: { if !$0 { viewModel.aiError = nil } }
        )) {
            Button("OK") { viewModel.aiError = nil }
        } message: {
            if let error = viewModel.aiError {
                Text(error)
            }
        }
    }
    #endif

    // MARK: - iOS Layout
    #if !os(macOS)
    private var iOSLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected Students
                if !viewModel.selectedStudentIDs.isEmpty {
                    SelectedStudentsBar(
                        students: students,
                        selectedStudentIDs: viewModel.selectedStudentIDs,
                        displayName: { viewModel.getDisplayName(for: $0, students: students) },
                        onRemove: { id in
                            withAnimation {
                                _ = viewModel.selectedStudentIDs.remove(id)
                            }
                        }
                    )
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.3))
                    Divider()
                }
                
                // Editor
                QuickNoteEditor(
                    bodyText: $viewModel.bodyText,
                    isFocused: $isFocused,
                    isProcessingAI: viewModel.isProcessingAI,
                    onTextChange: { viewModel.analyzeText($0, students: students) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Suggestions
                if !viewModel.detectedCandidateIDs.isEmpty {
                    SuggestionsBar(
                        students: students,
                        detectedCandidateIDs: viewModel.detectedCandidateIDs,
                        displayName: { viewModel.getDisplayName(for: $0, students: students) },
                        onAdd: { id in
                            withAnimation {
                                _ = viewModel.selectedStudentIDs.insert(id)
                                _ = viewModel.detectedCandidateIDs.remove(id)
                            }
                        }
                    )
                    .padding(.bottom, 8)
                }
                
                Divider()
                
                // Accessory Bar
                HStack(spacing: 16) {
                    // Date
                    ZStack {
                        DatePicker("", selection: $viewModel.noteDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .colorMultiply(.clear)
                            .background(
                                Image(systemName: "calendar")
                                    .foregroundStyle(Calendar.current.isDateInToday(viewModel.noteDate) ? .primary : Color.red)
                            )
                            .frame(width: 24, height: 24)
                            .fixedSize()
                    }
                    
                    // Category
                    Menu {
                        ForEach(NoteCategory.allCases, id: \.self) { cat in
                            Button { viewModel.category = cat } label: {
                                HStack {
                                    if viewModel.category == cat {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(cat.rawValue.capitalized)
                                }
                            }
                        }
                    } label: {
                        Circle()
                            .fill(viewModel.categoryColor(viewModel.category))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Divider
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 16)
                    
                    // Media & AI
                    PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo").font(.system(size: 20))
                    }
                    .foregroundStyle(.primary)
                    
                    Button { viewModel.isShowingCamera = true } label: {
                        Image(systemName: "camera").font(.system(size: 20))
                    }
                    .foregroundStyle(.primary)
                    
                    if viewModel.attachedImage != nil {
                        Image(systemName: "paperclip").foregroundStyle(.blue).font(.caption)
                    }

                    Spacer()
                    
                    // AI Sparkle
                    aiMenuButton(students: students)
                        .foregroundStyle(.purple)
                    
                    // Flag
                    Button { viewModel.includeInReport.toggle() } label: {
                        Image(systemName: viewModel.includeInReport ? "flag.fill" : "flag")
                            .foregroundStyle(viewModel.includeInReport ? .orange : .secondary)
                            .font(.system(size: 20))
                    }
                    
                    // Add Student
                    Button { viewModel.isShowingStudentPicker = true } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(Color.accentColor)
                            .font(.system(size: 20))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle("Quick Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { 
                        viewModel.saveNote(modelContext: modelContext)
                        dismiss()
                    }
                        .fontWeight(.bold)
                        .disabled(viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .popover(isPresented: $viewModel.isShowingStudentPicker) {
                StudentPickerPopover(
                    students: students,
                    selectedIDs: $viewModel.selectedStudentIDs,
                    onDone: { viewModel.isShowingStudentPicker = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $viewModel.isShowingCamera) {
                #if os(iOS)
                CameraView(image: Binding(
                    get: { viewModel.attachedImage },
                    set: { viewModel.attachedImage = $0 }
                )) { img in
                    if let img = img { viewModel.processImage(img) }
                }
                #endif
            }
            .alert("AI Error", isPresented: Binding(
                get: { viewModel.aiError != nil },
                set: { if !$0 { viewModel.aiError = nil } }
            )) {
                Button("OK") { viewModel.aiError = nil }
            } message: {
                if let error = viewModel.aiError {
                    Text(error)
                }
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in viewModel.loadPhoto(newItem) }
    }
    #endif
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func aiMenuButton(students: [Student]) -> some View {
        #if ENABLE_FOUNDATION_MODELS
        QuickNoteAIMenuButton(
            onFormatNames: { viewModel.formatNamesLocally(students: students) },
            onFixGrammar: { viewModel.runAI(instruction: AIPrompts.fixGrammar) },
            onProfessionalTone: { viewModel.runAI(instruction: AIPrompts.professionalTone) },
            onExpandNote: { viewModel.runAI(instruction: AIPrompts.expandNote) }
        )
        #else
        QuickNoteAIMenuButton(
            onFormatNames: { viewModel.formatNamesLocally(students: students) }
        )
        #endif
    }
}

