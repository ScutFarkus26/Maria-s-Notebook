import SwiftUI
import SwiftData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "Classification for a single note")
struct NoteClassificationSuggestion {
    @Guide(description: "One of: academic, behavioral, social, emotional, health, attendance, general")
    var category: String

    @Guide(description: "IDs or names indicating student-specific scope; empty means all")
    var studentIdentifiers: [String]
}
#endif

/// A unified note editor that works for all note types in the app
/// Based on QuickNoteSheet but supports all contexts
struct UnifiedNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Context configuration
    enum NoteContext {
        case general
        case lesson(Lesson)
        case work(WorkModel)
        case studentLesson(StudentLesson)
        case presentation(Presentation)
        case attendance(AttendanceRecord)
        case workCheckIn(WorkCheckIn)
        case workCompletion(WorkCompletionRecord)
        case workPlanItem(WorkPlanItem)
        case studentMeeting(StudentMeeting)
        case projectSession(ProjectSession)
        case communityTopic(CommunityTopic)
        case reminder(Reminder)
        case schoolDayOverride(SchoolDayOverride)
    }
    
    let context: NoteContext
    let initialNote: Note? // For editing existing notes
    let onSave: (Note) -> Void
    let onCancel: () -> Void
    
    @Query(sort: [
        SortDescriptor(\Student.firstName),
        SortDescriptor(\Student.lastName)
    ]) private var students: [Student]
    
    // State (same as QuickNoteSheet)
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var detectedStudentIDs: Set<UUID> = []
    @State private var category: NoteCategory = .general
    @State private var bodyText: String = ""
    @State private var includeInReport: Bool = false
    @State private var showingStudentPicker: Bool = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    #if os(iOS)
    @State private var showingCamera: Bool = false
    #endif
    #if os(macOS)
    @State private var selectedImage: NSImage? = nil
    #else
    @State private var selectedImage: UIImage? = nil
    #endif
    @State private var imagePath: String? = nil
    
    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @State private var isSuggesting: Bool = false
    @State private var showingSuggestionSheet: Bool = false
    @State private var proposedCategory: NoteCategory? = nil
    @State private var proposedStudentIDs: [UUID] = []
    @State private var suggestionError: String? = nil
    #endif
    
    // AI / Smart Editor State
    @State private var aiTriggerCounter: Int = 0
    
    private let tagger = StudentTagger()
    @State private var nameDetectionTask: Task<Void, Never>? = nil
    
    // Computed properties for context-specific behavior
    private var contextTitle: String {
        switch context {
        case .general: return "Quick Note"
        case .lesson: return "Lesson Note"
        case .work: return "Work Note"
        case .studentLesson: return "Presentation Note"
        case .presentation: return "Presentation Note"
        case .attendance: return "Attendance Note"
        case .workCheckIn: return "Check-In Note"
        case .workCompletion: return "Completion Note"
        case .workPlanItem: return "Plan Note"
        case .studentMeeting: return "Meeting Note"
        case .projectSession: return "Session Note"
        case .communityTopic: return "Topic Note"
        case .reminder: return "Reminder Note"
        case .schoolDayOverride: return "Override Note"
        }
    }
    
    private var shouldShowStudentSelection: Bool {
        switch context {
        case .attendance, .workCompletion, .studentMeeting:
            // These have inherent student context
            return false
        default:
            return true
        }
    }
    
    private var preSelectedStudents: Set<UUID> {
        switch context {
        case .attendance(let record):
            if let studentID = UUID(uuidString: record.studentID) {
                return [studentID]
            }
        case .workCompletion(let record):
            if let studentID = UUID(uuidString: record.studentID) {
                return [studentID]
            }
        case .studentMeeting(let meeting):
            if let studentID = UUID(uuidString: meeting.studentID) {
                return [studentID]
            }
        case .studentLesson(let sl):
            return Set(sl.studentIDs.compactMap { UUID(uuidString: $0) })
        case .work(let work):
            // Extract from participants if available
            return Set((work.participants ?? []).compactMap { UUID(uuidString: $0.studentID) })
        default:
            break
        }
        return []
    }
    
    var body: some View {
        Group {
            // Same UI structure as QuickNoteSheet
            #if os(macOS)
            VStack(alignment: .leading, spacing: 20) {
                headerView
                ScrollView {
                    mainContentCard
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                actionButtons
            }
            .padding(24)
            .frame(width: 480, height: 560)
            .presentationSizingFitted()
            #else
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mainContentCard
                    }
                    .padding(24)
                }
                .navigationTitle(contextTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveNote()
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        .sheet(isPresented: $showingSuggestionSheet) {
            SuggestionPreviewSheet(
                proposedCategory: proposedCategory,
                proposedStudentIDs: proposedStudentIDs,
                allStudents: students,
                onApply: {
                    if let cat = proposedCategory { self.category = cat }
                    if !proposedStudentIDs.isEmpty { self.selectedStudentIDs = Set(proposedStudentIDs) }
                    showingSuggestionSheet = false
                },
                onCancel: {
                    showingSuggestionSheet = false
                }
            )
        }
        .alert("AI Suggestion Error", isPresented: Binding(
            get: { suggestionError != nil },
            set: { if !$0 { suggestionError = nil } }
        )) {
            Button("OK") { suggestionError = nil }
        } message: {
            if let error = suggestionError {
                Text(error)
            }
        }
#endif
        .onAppear {
            setupInitialState()
        }
        .onChange(of: bodyText) { _, newText in
            if shouldShowStudentSelection {
                nameDetectionTask?.cancel()
                nameDetectionTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if Task.isCancelled { return }
                    await analyzeTextForNames(newText)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            handlePhotoChange(newItem)
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $selectedImage) { img in
                if let img = img {
                    handleCameraImage(img)
                }
            }
        }
        #endif
    }
    
    private func setupInitialState() {
        // Pre-select students based on context
        selectedStudentIDs = preSelectedStudents
        
        // Load existing note if editing
        if let note = initialNote {
            bodyText = note.body
            category = note.category
            includeInReport = note.includeInReport
            imagePath = note.imagePath
            
            // Extract student IDs from scope
            switch note.scope {
            case .student(let id):
                selectedStudentIDs = [id]
            case .students(let ids):
                selectedStudentIDs = Set(ids)
            case .all:
                break
            }
        } else {
            // Default category for specific contexts
            if case .attendance = context {
                category = .attendance
            }
        }
    }
    
    // MARK: - View Components (copied from QuickNoteSheet)
    
    private var headerView: some View {
        HStack {
            Text(contextTitle)
                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
            Spacer()
        }
    }
    
    private var mainContentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowStudentSelection {
                surfacingBanner
                studentSelectionSection
            }
            categorySelectionSection
            noteBodySection
            reportToggleSection
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
    
    @ViewBuilder
    private var surfacingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Names")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(detectedStudentIDs), id: \.self) { studentID in
                        if let student = students.first(where: { $0.id == studentID }) {
                            Button {
                                if selectedStudentIDs.contains(studentID) {
                                    selectedStudentIDs.remove(studentID)
                                } else {
                                    selectedStudentIDs.insert(studentID)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(displayName(for: student))
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                    if selectedStudentIDs.contains(studentID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(selectedStudentIDs.contains(studentID) ? .accentColor : .primary)
                                .background(
                                    Capsule()
                                        .fill(selectedStudentIDs.contains(studentID) ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minHeight: 44)
        .opacity(detectedStudentIDs.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: detectedStudentIDs)
        .accessibilityHidden(detectedStudentIDs.isEmpty)
    }
    
    private var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Students")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedStudentIDs), id: \.self) { studentID in
                            if let student = students.first(where: { $0.id == studentID }) {
                                HStack(spacing: 4) {
                                    Text(displayName(for: student))
                                        .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                                    Button {
                                        selectedStudentIDs.remove(studentID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(.primary)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                Button {
                    showingStudentPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(.accentColor)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStudentPicker, arrowEdge: .top) {
                    studentPickerPopover
                }
            }
        }
    }
    
    private var studentPickerPopover: some View {
        StudentPickerPopover(
            students: students,
            selectedIDs: $selectedStudentIDs,
            onDone: {
                showingStudentPicker = false
            }
        )
        .padding(12)
        .frame(minWidth: 320)
    }
    
    private var categorySelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Category")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
                if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await suggestCategoryAndScope() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text(isSuggesting ? "Suggesting…" : "Suggest")
                        }
                    }
                    .disabled(isSuggesting)
                }
#endif
            }
            
            Picker("Category", selection: $category) {
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private var noteBodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                
                // THE "AI TOOLS" BUTTON
                if !bodyText.isEmpty {
                    if #available(iOS 18.0, macOS 15.0, *) {
                        Button {
                            // Triggers the Select All + Invoke logic
                            aiTriggerCounter += 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Writing Tools")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.purple)
                        #if os(iOS)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                        #endif
                    }
                }
            }
            
            // USE CUSTOM SMART EDITOR
            SmartTextEditor(text: $bodyText, triggerTool: $aiTriggerCounter)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(notesBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                expandInitialsButton
                Spacer()
            }
            
            photoPickerSection
        }
    }
    
    private var photoPickerSection: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            cameraButton
            #endif
            photoPickerButton
            photoPreview
            Spacer()
        }
    }
    
    #if os(iOS)
    private var cameraButton: some View {
        Button {
            showingCamera = true
        } label: {
            Label("Take Photo", systemImage: "camera.fill")
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    #endif
    
    private var photoPickerButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var expandInitialsButton: some View {
        Button {
            expandInitialsInBodyText()
        } label: {
            Label("Expand Initials", systemImage: "textformat.abc")
                .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    @ViewBuilder
    private var photoPreview: some View {
        if selectedImage != nil {
            photoPreviewContent
        }
    }
    
    @ViewBuilder
    private var photoPreviewContent: some View {
        HStack(spacing: 8) {
            photoThumbnailView
            
            Button {
                selectedPhoto = nil
                selectedImage = nil
                imagePath = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var photoThumbnailView: some View {
        Group {
            #if os(macOS)
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            #else
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            #endif
        }
    }
    
    private var reportToggleSection: some View {
        Toggle("Flag for Report", isOn: $includeInReport)
            .font(.system(size: AppTheme.FontSize.body, design: .rounded))
    }
    
    private var actionButtons: some View {
        HStack {
            Spacer()
            
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button("Save") {
                saveNote()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }
    
    private var canSave: Bool {
        if !shouldShowStudentSelection {
            return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !selectedStudentIDs.isEmpty && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Helper Methods (copied from QuickNoteSheet)
    
    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = student.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }
    
    private func handlePhotoChange(_ newItem: PhotosPickerItem?) {
        Task {
            if let newItem = newItem {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    #if os(macOS)
                    if let image = NSImage(data: data) {
                        selectedImage = image
                        do {
                            imagePath = try PhotoStorageService.saveImage(image)
                        } catch {
                            print("Error saving image: \(error)")
                            selectedImage = nil
                            selectedPhoto = nil
                        }
                    }
                    #else
                    if let image = UIImage(data: data) {
                        handleCameraImage(image)
                    }
                    #endif
                }
            } else {
                selectedImage = nil
                imagePath = nil
            }
        }
    }
    
    #if os(iOS)
    private func handleCameraImage(_ image: UIImage) {
        selectedImage = image
        do {
            imagePath = try PhotoStorageService.saveImage(image)
        } catch {
            print("Error saving image: \(error)")
            selectedImage = nil
        }
    }
    #endif
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
    
    private var notesBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
        #endif
    }
    
    private func analyzeTextForNames(_ text: String) async {
        detectedStudentIDs.removeAll()
        guard !text.isEmpty else { return }
        
        let studentData = students.map { student in
            StudentData(
                id: student.id,
                firstName: student.firstName,
                lastName: student.lastName,
                nickname: student.nickname
            )
        }
        
        let result = await tagger.findStudentMatches(in: text, studentData: studentData)
        
        // Populate detected IDs from both exact and fuzzy matches
        detectedStudentIDs = result.exact.union(result.fuzzy)
        
        // Auto-select unique matches without overriding user choices
        let newAutoSelects = result.autoSelect.subtracting(selectedStudentIDs)
        if !newAutoSelects.isEmpty {
            selectedStudentIDs.formUnion(newAutoSelects)
        }
    }

    private func expandInitialsInBodyText() {
        let text = bodyText
        guard !text.isEmpty else { return }

        // Build a map from lowercase initials (e.g., "dd") to students
        var initialsMap: [String: [Student]] = [:]
        for s in students {
            let first = s.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = s.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let fi = first.first, let li = last.first else { continue }
            let key = String(fi).lowercased() + String(li).lowercased()
            initialsMap[key, default: []].append(s)
        }

        // Match uppercase two-letter initials with optional dots/spaces: "DD", "D.D.", "D D", "D. D"
        let pattern = "\\b([A-Z])\\.?\\s*([A-Z])\\.?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        var newText = text
        var delta = 0

        regex.enumerateMatches(in: text, options: [], range: nsrange) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 3,
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text) else { return }

            let l1 = String(text[r1]).lowercased()
            let l2 = String(text[r2]).lowercased()
            let key = l1 + l2

            guard let candidates = initialsMap[key], candidates.count == 1, let student = candidates.first else { return }

            let first = student.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastInitial = student.lastName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? ""
            let replacement = lastInitial.isEmpty ? first : "\(first) \(lastInitial)"

            // Apply replacement in the accumulating newText using adjusted range
            let loc = match.range.location + delta
            let len = match.range.length
            let startIdx = newText.index(newText.startIndex, offsetBy: loc)
            let endIdx = newText.index(startIdx, offsetBy: len)
            newText.replaceSubrange(startIdx..<endIdx, with: replacement)
            delta += replacement.count - len
        }

        bodyText = newText
    }
    
#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @MainActor
    private func suggestCategoryAndScope() async {
        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSuggesting = true
        defer { isSuggesting = false }

        let session = LanguageModelSession(
            instructions: AIPrompts.noteClassification
        )
        do {
            let response = try await session.respond(
                to: AIPrompts.classifyNote(bodyText),
                generating: NoteClassificationSuggestion.self,
                options: .init(temperature: 0.2)
            )
            let content = response.content
            // Category
            let proposedCat = NoteCategory(rawValue: content.category.lowercased()) ?? .general
            // Map names/identifiers to IDs by matching first name, nickname, or full name (case-insensitive)
            let ids: [UUID] = content.studentIdentifiers.compactMap { ident in
                let token = ident.folding(options: .diacriticInsensitive, locale: .current).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return students.first(where: { s in
                    let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let full = (first + " " + last)
                    return token == full || token == first || (!nick.isEmpty && token == nick)
                })?.id
            }
            self.proposedCategory = proposedCat
            self.proposedStudentIDs = Array(Set(ids))
            self.showingSuggestionSheet = true
        } catch {
            self.suggestionError = error.localizedDescription
        }
    }

    // A small sheet to preview and apply suggestions
    private struct SuggestionPreviewSheet: View {
        let proposedCategory: NoteCategory?
        let proposedStudentIDs: [UUID]
        let allStudents: [Student]
        let onApply: () -> Void
        let onCancel: () -> Void

        private func name(for id: UUID) -> String {
            if let s = allStudents.first(where: { $0.id == id }) {
                let first = s.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let lastI = s.lastName.first.map { String($0).uppercased() } ?? ""
                return lastI.isEmpty ? first : "\(first) \(lastI)."
            }
            return "Unknown"
        }

        var body: some View {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                Text("Suggested Classification")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if let cat = proposedCategory {
                    HStack {
                        Text("Category:").bold()
                        Text(cat.rawValue.capitalized)
                    }
                }
                if !proposedStudentIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scope:").bold()
                        ForEach(proposedStudentIDs, id: \.self) { id in
                            Text(name(for: id))
                        }
                    }
                } else {
                    HStack { Text("Scope:").bold(); Text("All Students") }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { onCancel() }
                    Button("Apply") { onApply() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
            .presentationSizingFitted()
            #else
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    if let cat = proposedCategory {
                        HStack {
                            Text("Category:").bold()
                            Text(cat.rawValue.capitalized)
                        }
                    }
                    if !proposedStudentIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scope:").bold()
                            ForEach(proposedStudentIDs, id: \.self) { id in
                                Text(name(for: id))
                            }
                        }
                    } else {
                        HStack { Text("Scope:").bold(); Text("All Students") }
                    }
                    Spacer()
                }
                .padding(20)
                .navigationTitle("Suggested Classification")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply() } }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
#endif
    
    private func saveNote() {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        
        // Determine scope based on context and selection
        let scope: NoteScope
        
        // Use selectedStudentIDs (which is populated from context if picker is hidden)
        // Fix: Use selectedStudentIDs if present, even if selection UI is hidden
        if selectedStudentIDs.isEmpty {
            scope = .all
        } else if selectedStudentIDs.count == 1 {
            scope = .student(selectedStudentIDs.first!)
        } else {
            scope = .students(Array(selectedStudentIDs))
        }
        
        let note: Note
        if let existing = initialNote {
            // Update existing note
            existing.body = trimmedBody
            existing.category = category
            existing.includeInReport = includeInReport
            existing.imagePath = imagePath
            existing.updatedAt = Date()
            existing.scope = scope
            note = existing
        } else {
            // Create new note with context-specific relationship
            note = Note(
                body: trimmedBody,
                scope: scope,
                category: category,
                includeInReport: includeInReport,
                imagePath: imagePath
            )
            
            // Set the appropriate relationship based on context
            // Task requirement #2: Verify each NoteContext sets the correct relationship
            var studentLessonID: String? = nil
            var presentationID: String? = nil
            var workID: String? = nil
            
            switch context {
            case .lesson(let lesson):
                note.lesson = lesson
            case .work(let work):
                note.work = work
                workID = work.id.uuidString
            case .studentLesson(let sl):
                note.studentLesson = sl
                studentLessonID = sl.id.uuidString
            case .presentation(let presentation):
                note.presentation = presentation
                // If presentation has a legacyStudentLessonID, fetch and link the StudentLesson
                if let legacyIDString = presentation.legacyStudentLessonID,
                   let legacyID = UUID(uuidString: legacyIDString) {
                    let descriptor = FetchDescriptor<StudentLesson>(
                        predicate: #Predicate { $0.id == legacyID }
                    )
                    if let studentLesson = try? modelContext.fetch(descriptor).first {
                        note.studentLesson = studentLesson
                    }
                }
                presentationID = presentation.id.uuidString
            case .attendance(let record):
                note.attendanceRecord = record
            case .workCheckIn(let checkIn):
                note.workCheckIn = checkIn
            case .workCompletion(let record):
                note.workCompletionRecord = record
            case .workPlanItem(let item):
                note.workPlanItem = item
            case .studentMeeting(let meeting):
                note.studentMeeting = meeting
            case .projectSession(let session):
                note.projectSession = session
            case .communityTopic(let topic):
                note.communityTopic = topic
            case .reminder(let reminder):
                note.reminder = reminder
            case .schoolDayOverride(let override):
                note.schoolDayOverride = override
            case .general:
                break
            }
            
            // Task requirement #1: Add one-time diagnostic log
            print("=== UnifiedNoteEditor.saveNote() Diagnostic ===")
            print("NoteContext case: \(contextDescription)")
            print("note.id: \(note.id.uuidString)")
            if let slID = studentLessonID {
                print("studentLessonID: \(slID)")
            }
            if let pID = presentationID {
                print("presentationID: \(pID)")
            }
            if let wID = workID {
                print("workID: \(wID)")
            }
            print("=== End Diagnostic ===")
            
            modelContext.insert(note)
        }
        
        try? modelContext.save()
        onSave(note)
        dismiss()
    }
    
    // Helper to describe context for logging
    private var contextDescription: String {
        switch context {
        case .general: return ".general"
        case .lesson: return ".lesson"
        case .work: return ".work"
        case .studentLesson: return ".studentLesson"
        case .presentation: return ".presentation"
        case .attendance: return ".attendance"
        case .workCheckIn: return ".workCheckIn"
        case .workCompletion: return ".workCompletion"
        case .workPlanItem: return ".workPlanItem"
        case .studentMeeting: return ".studentMeeting"
        case .projectSession: return ".projectSession"
        case .communityTopic: return ".communityTopic"
        case .reminder: return ".reminder"
        case .schoolDayOverride: return ".schoolDayOverride"
        }
    }
}

// MARK: - Smart Text Editor (The Magic Sauce)
// SmartTextEditor is now in UnifiedNoteEditor/SmartTextEditor.swift
