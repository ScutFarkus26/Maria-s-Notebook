// swiftlint:disable file_length
import OSLog
import SwiftUI
import CoreData
import PhotosUI

// MARK: - QuickNoteSheet
// swiftlint:disable:next type_body_length
struct QuickNoteSheet: View {
    private static let logger = Logger.notes

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - Data
    @FetchRequest(sortDescriptors: CDStudent.sortByName)private var studentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.id, ascending: true)]) private var lessons: FetchedResults<CDLesson>
    private var selectedLesson: CDLesson? {
        guard let id = viewModel.selectedLessonID else { return nil }
        return lessons.first { $0.id == id }
    }

    // MARK: - View Model
    @State private var viewModel: QuickNoteViewModel

    // MARK: - UI State
    @FocusState private var isFocused: Bool
    @State private var showQuickTags: Bool = false

    // MARK: - Init

    /// Backward-compatible init for single-student callers (pie menu, TodayView, etc.)
    init(initialStudentID: UUID? = nil, initialBodyText: String = "") {
        let ids: Set<UUID> = initialStudentID.map { Set([$0]) } ?? []
        _viewModel = State(wrappedValue: QuickNoteViewModel(
            initialStudentIDs: ids,
            initialBodyText: initialBodyText
        ))
    }

    /// Full init for command bar routing with multi-student + tag pre-selection
    init(initialStudentIDs: Set<UUID>, initialBodyText: String = "", initialTags: [String] = []) {
        _viewModel = State(wrappedValue: QuickNoteViewModel(
            initialStudentIDs: initialStudentIDs,
            initialBodyText: initialBodyText,
            initialTags: initialTags
        ))
    }
    
    // MARK: - Body
    var body: some View {
        actualView
            .task {
                // Update view model with students once available
                // CDNote: ViewModel holds students for display name logic
                viewModel.setupInitialState()
                
                // Brief delay for sheet animation to complete
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    Self.logger.warning("Failed to delay focus: \(error)")
                }
                isFocused = true
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
        NavigationStack {
            HStack(spacing: 0) {
                // Sidebar Metadata
                VStack(alignment: .leading, spacing: 20) {
                    // Date Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Date", systemImage: SFSymbol.Time.calendar)
                            .font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $viewModel.noteDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact)
                    }
                    
                    // Montessori Quick Tags
                    ObservationQuickTagBar(selectedTags: $viewModel.tags)

                    // Custom Tags (non-Montessori tags added via full picker)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Custom Tags", systemImage: "tag")
                            .font(.caption).foregroundStyle(.secondary)

                        let quickTagSet = Set(MontessoriObservationTags.allTags + DevelopmentalCharacteristic.allCases.map(\.tag))
                        let customTags = viewModel.tags.filter { !quickTagSet.contains($0) }

                        FlowLayout(spacing: 4) {
                            ForEach(customTags, id: \.self) { tag in
                                TagBadge(tag: tag, compact: true)
                            }

                            Button {
                                viewModel.showingTagPicker = true
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .sheet(isPresented: $viewModel.showingTagPicker) {
                        NoteTagPickerSheet(selectedTags: $viewModel.tags)
                            .frame(minWidth: 400, minHeight: 400)
                    }

                    // CDLesson
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Lesson", systemImage: SFSymbol.Education.book)
                            .font(.caption).foregroundStyle(.secondary)

                        if let lesson = selectedLesson {
                            QuickNoteLessonChip(
                                lessonName: lesson.name,
                                subject: lesson.subject
                            ) {
                                adaptiveWithAnimation { viewModel.selectedLessonID = nil }
                            }
                        }

                        Button {
                            viewModel.isShowingLessonPicker = true
                        } label: {
                            Label(
                                selectedLesson != nil ? "Change" : "Add",
                                systemImage: selectedLesson != nil ? "arrow.triangle.2.circlepath" : "plus"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .popover(isPresented: $viewModel.isShowingLessonPicker) {
                        QuickNoteLessonPicker(
                            selectedLessonID: $viewModel.selectedLessonID,
                            onDone: { viewModel.isShowingLessonPicker = false }
                        )
                    }

                    // Flags
                    Toggle(isOn: $viewModel.needsFollowUp) {
                        Label("Follow-Up", systemImage: SFSymbol.Rating.flag)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Toggle(isOn: $viewModel.includeInReport) {
                        Label("Flag for Report", systemImage: "doc.text")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Spacer()
                }
                .padding()
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor).opacity(UIConstants.OpacityConstants.half))
                
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
                                adaptiveWithAnimation {
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
                                adaptiveWithAnimation {
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
            .navigationTitle("New Note")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveNote(viewContext: viewContext)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(viewModel.bodyText.trimmed().isEmpty)
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
                            adaptiveWithAnimation {
                                _ = viewModel.selectedStudentIDs.remove(id)
                            }
                        }
                    )
                    .background(Color(uiColor: .secondarySystemBackground).opacity(UIConstants.OpacityConstants.semi))
                    Divider()
                }

                // Selected CDLesson
                if let lesson = selectedLesson {
                    HStack {
                        QuickNoteLessonChip(
                            lessonName: lesson.name,
                            subject: lesson.subject
                        ) {
                            adaptiveWithAnimation { viewModel.selectedLessonID = nil }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(UIConstants.OpacityConstants.semi))
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
                            adaptiveWithAnimation {
                                _ = viewModel.selectedStudentIDs.insert(id)
                                _ = viewModel.detectedCandidateIDs.remove(id)
                            }
                        }
                    )
                    .padding(.bottom, 8)
                }

                // Montessori Quick Tags
                if showQuickTags {
                    ObservationQuickTagBar(selectedTags: $viewModel.tags)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider()

                iOSAccessoryBar(students: students)
            }
            .navigationTitle("Quick Note")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { 
                        viewModel.saveNote(viewContext: viewContext)
                        dismiss()
                    }
                        .fontWeight(.bold)
                        .disabled(viewModel.bodyText.trimmed().isEmpty)
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
            .sheet(isPresented: $viewModel.showingTagPicker) {
                NoteTagPickerSheet(selectedTags: $viewModel.tags)
                    .presentationDetents([.medium, .large])
            }
            .popover(isPresented: $viewModel.isShowingLessonPicker) {
                QuickNoteLessonPicker(
                    selectedLessonID: $viewModel.selectedLessonID,
                    onDone: { viewModel.isShowingLessonPicker = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $viewModel.isShowingCamera) {
                #if os(iOS)
                CameraView(image: Binding(
                    get: { viewModel.attachedImage },
                    set: { viewModel.attachedImage = $0 }
                )) { img in
                    if let img { viewModel.processImage(img) }
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

    // Extracted accessory bar to reduce type-checker complexity in iOSLayout.
    // swiftlint:disable:next function_body_length
    private func iOSAccessoryBar(students: [CDStudent]) -> some View {
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

            // Tags — tap toggles quick tags, long press opens full picker
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    showQuickTags.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    if !viewModel.tags.isEmpty {
                        Text("\(viewModel.tags.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .foregroundStyle(showQuickTags ? Color.accentColor : (viewModel.tags.isEmpty ? Color.primary : Color.blue))
                .font(AppTheme.ScaledFont.titleMedium)
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                viewModel.showingTagPicker = true
            })

            // Divider
            Rectangle().fill(Color.secondary.opacity(UIConstants.OpacityConstants.semi)).frame(width: 1, height: 16)

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

            // CDLesson
            Button { viewModel.isShowingLessonPicker = true } label: {
                Image(systemName: SFSymbol.Education.book)
                    .foregroundStyle(viewModel.selectedLessonID != nil ? Color.indigo : Color.primary)
                    .font(.system(size: 20))
            }

            Spacer()

            // AI Sparkle
            aiMenuButton(students: students)
                .foregroundStyle(.purple)

            // Follow-up flag
            Button { viewModel.needsFollowUp.toggle() } label: {
                Image(systemName: viewModel.needsFollowUp ? "flag.fill" : "flag")
                    .foregroundStyle(viewModel.needsFollowUp ? .red : .secondary)
                    .font(.system(size: 20))
            }

            // Report flag
            Button { viewModel.includeInReport.toggle() } label: {
                Image(systemName: viewModel.includeInReport ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(viewModel.includeInReport ? .orange : .secondary)
                    .font(.system(size: 20))
            }

            // Add CDStudent
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
    #endif

    // MARK: - Helper Views

    @ViewBuilder
    private func aiMenuButton(students: [CDStudent]) -> some View {
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
