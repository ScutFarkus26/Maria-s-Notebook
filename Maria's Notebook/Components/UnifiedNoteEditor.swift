import SwiftUI
import SwiftData
import PhotosUI
import NaturalLanguage

#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
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
        case workContract(WorkContract)
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
    
    private let tagger = NLTagger(tagSchemes: [.nameType])
    @State private var nameDetectionTask: Task<Void, Never>? = nil
    
    // Computed properties for context-specific behavior
    private var contextTitle: String {
        switch context {
        case .general: return "Quick Note"
        case .lesson: return "Lesson Note"
        case .work: return "Work Note"
        case .studentLesson: return "Presentation Note"
        case .presentation: return "Presentation Note"
        case .workContract: return "Work Contract Note"
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
        .onAppear {
            setupInitialState()
        }
        .onChange(of: bodyText) { _, newText in
            if shouldShowStudentSelection {
                nameDetectionTask?.cancel()
                nameDetectionTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if Task.isCancelled { return }
                    analyzeTextForNames(newText)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            handlePhotoChange(newItem)
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraPicker(image: Binding(
                get: { nil },
                set: { newImage in
                    if let newImage = newImage {
                        handleCameraImage(newImage)
                    }
                }
            ))
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
            Text("Category")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
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
            Text("Note")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            noteTextEditor
            
            HStack {
                expandInitialsButton
                Spacer()
            }
            
            photoPickerSection
        }
    }
    
    private var noteTextEditor: some View {
        TextEditor(text: $bodyText)
            .font(.system(size: AppTheme.FontSize.body, design: .rounded))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
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
    
    private func analyzeTextForNames(_ text: String) {
        detectedStudentIDs.removeAll()
        guard !text.isEmpty else { return }

        // Normalize the full text for manual scanning
        let haystack = text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        // Precompute name maps for uniqueness checks
        var firstNameCounts: [String: Int] = [:]
        var nicknameCounts: [String: Int] = [:]
        var fullNameCounts: [String: Int] = [:]
        var initialsMap: [String: [UUID]] = [:]

        for s in students {
            let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            firstNameCounts[first, default: 0] += 1
            if let nickRaw = s.nickname, !nickRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let nick = nickRaw.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                nicknameCounts[nick, default: 0] += 1
            }
            let full = (first + " " + last).trimmingCharacters(in: .whitespacesAndNewlines)
            fullNameCounts[full, default: 0] += 1
            if let fi = first.first, let li = last.first {
                let key = String(fi) + String(li)
                initialsMap[key, default: []].append(s.id)
            }
        }

        var autoSelectCandidates: Set<UUID> = []

        // Pass 1: NLTagger over detected personal-name tokens
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                let token = String(text[tokenRange])
                let normToken = token.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                let lettersOnly = normToken.filter { $0.isLetter }

                // Detection (fuzzy and structured)
                for student in students {
                    if matches(student: student, with: token) {
                        detectedStudentIDs.insert(student.id)
                    }
                }

                // Auto-select: unique initials, unique exact first, unique exact nickname, unique exact full name
                if lettersOnly.count == 2 {
                    let key = String(lettersOnly)
                    if let ids = initialsMap[key], ids.count == 1, let only = ids.first {
                        autoSelectCandidates.insert(only)
                    }
                } else {
                    for s in students {
                        let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                        let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                        let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
                        let full = (first + " " + last)

                        if normToken == full, fullNameCounts[full] == 1 { autoSelectCandidates.insert(s.id); continue }
                        if !nick.isEmpty, normToken == nick, nicknameCounts[nick] == 1 { autoSelectCandidates.insert(s.id); continue }
                        if normToken == first, firstNameCounts[first] == 1 { autoSelectCandidates.insert(s.id); continue }
                    }
                }
            }
            return true
        }

        // Pass 2: Manual scan of the full text to catch patterns not tagged by NLTagger
        for s in students {
            let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let full = first + " " + last

            // Nickname word
            if !nick.isEmpty, containsWord(haystack, word: nick) {
                detectedStudentIDs.insert(s.id)
                if nicknameCounts[nick] == 1 { autoSelectCandidates.insert(s.id) }
                continue
            }
            // First name word
            if containsWord(haystack, word: first) {
                detectedStudentIDs.insert(s.id)
                if firstNameCounts[first] == 1 { autoSelectCandidates.insert(s.id) }
                continue
            }
            // Full name words
            if containsFirstAndLast(haystack, first: first, last: last) {
                detectedStudentIDs.insert(s.id)
                if fullNameCounts[full] == 1 { autoSelectCandidates.insert(s.id) }
                continue
            }
            // Compact or punctuated initials
            if let fi = first.first, let li = last.first, containsInitials(haystack, firstInitial: fi, lastInitial: li) {
                detectedStudentIDs.insert(s.id)
                let key = String(fi) + String(li)
                if let ids = initialsMap[key], ids.count == 1 { autoSelectCandidates.insert(s.id) }
                continue
            }
            // First + last initial (e.g., "ashira b" or "ashira b.")
            if containsFirstAndLastInitial(haystack, first: first, lastInitial: last.prefix(1)) {
                detectedStudentIDs.insert(s.id)
                continue
            }
        }

        // Apply auto-selection without overriding user choices
        selectedStudentIDs.formUnion(autoSelectCandidates)
    }

    private func matches(student: Student, with detectedToken: String) -> Bool {
        func norm(_ s: String) -> String {
            s.folding(options: .diacriticInsensitive, locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = norm(detectedToken).lowercased()
        let first = norm(student.firstName).lowercased()
        let last = norm(student.lastName).lowercased()
        let nick = norm(student.nickname ?? "").lowercased()

        // Handle compact two-letter initials like "ab" (no punctuation/space)
        let lettersOnly = token.filter { $0.isLetter }
        if lettersOnly.count == 2 {
            if let sfi = first.first, let sli = last.first {
                let fi = Character(String(sfi).lowercased())
                let li = Character(String(sli).lowercased())
                if lettersOnly.first == fi && lettersOnly.last == li {
                    return true
                }
            }
        }

        // Split token on whitespace/punctuation to handle "First Last" or "First L."
        let parts = token.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        if parts.count >= 2 {
            let firstPart = String(parts[0])
            let lastPart = String(parts[1])

            // First name or nickname fuzzy match (abbreviation supported via isFuzzyMatch)
            let firstMatches = firstPart.isFuzzyMatch(to: first) || (!nick.isEmpty && firstPart.isFuzzyMatch(to: nick))
            // Last name or last initial
            let lastInitial = lastPart.replacingOccurrences(of: ".", with: "").prefix(1)
            let lastMatches = lastPart.isFuzzyMatch(to: last) || (!lastInitial.isEmpty && last.lowercased().hasPrefix(lastInitial.lowercased()))
            return firstMatches && lastMatches
        } else {
            // Single token: compare against first, nickname, or last with fuzzy match
            return token.isFuzzyMatch(to: first)
                || (!nick.isEmpty && token.isFuzzyMatch(to: nick))
                || token.isFuzzyMatch(to: last)
        }
    }

    private func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func containsFirstAndLastInitial(_ text: String, first: String, lastInitial: Substring) -> Bool {
        guard !first.isEmpty, let li = lastInitial.first else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: String(li)) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func containsFirstAndLast(_ text: String, first: String, last: String) -> Bool {
        guard !first.isEmpty, !last.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + "\\s+" + NSRegularExpression.escapedPattern(for: last) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func containsInitials(_ text: String, firstInitial: Character, lastInitial: Character) -> Bool {
        let fi = String(firstInitial).lowercased()
        let li = String(lastInitial).lowercased()
        // Matches: "a b", "a.b.", "ab" with word boundaries
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: fi) + "\\.?\\s*" + NSRegularExpression.escapedPattern(for: li) + "\\.?\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
    
    private func saveNote() {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        
        // Determine scope based on context and selection
        let scope: NoteScope
        if !shouldShowStudentSelection || selectedStudentIDs.isEmpty {
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
            switch context {
            case .lesson(let lesson):
                note.lesson = lesson
            case .work(let work):
                note.work = work
            case .studentLesson(let sl):
                note.studentLesson = sl
            case .presentation(let presentation):
                note.presentation = presentation
            case .workContract(let contract):
                note.workContract = contract
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
            
            modelContext.insert(note)
        }
        
        try? modelContext.save()
        onSave(note)
        dismiss()
    }
}

#if os(iOS)
/// Camera picker wrapper for UIImagePickerController
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

