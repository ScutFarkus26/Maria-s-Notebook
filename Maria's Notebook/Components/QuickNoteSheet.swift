import SwiftUI
import SwiftData
import PhotosUI
import NaturalLanguage

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - QuickNoteSheet
struct QuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Data
    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var students: [Student]
    
    // MARK: - State
    // Note Content
    @State private var bodyText: String = ""
    @State private var category: NoteCategory = .general
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var includeInReport: Bool = false
    @State private var noteDate: Date = Date()
    
    // Attachments
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var attachedImage: PlatformImage? = nil
    @State private var attachedImagePath: String? = nil
    
    // UI State
    @State private var detectedCandidateIDs: Set<UUID> = []
    @State private var isShowingStudentPicker: Bool = false
    @State private var isShowingCamera: Bool = false
    @FocusState private var isFocused: Bool
    
    // Logic
    private let tagger = NLTagger(tagSchemes: [.nameType])
    private let initialStudentID: UUID?

    // MARK: - Init
    init(initialStudentID: UUID? = nil) {
        self.initialStudentID = initialStudentID
    }

    // MARK: - Body
    var body: some View {
        #if os(macOS)
        macOSLayout
            .frame(minWidth: 600, minHeight: 500)
            .onAppear(perform: setupInitialState)
        #else
        iOSLayout
            .onAppear(perform: setupInitialState)
        #endif
    }
    
    // MARK: - Initial Setup
    private func setupInitialState() {
        if let initialID = initialStudentID {
            selectedStudentIDs.insert(initialID)
        }
        // Delay focus slightly to allow transition to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isFocused = true
        }
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // macOS Header
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
                    
                    Button("Save") { saveNote() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Main Content Area
            HStack(spacing: 0) {
                // Left: Sidebar-ish metadata (Things 3 Mac style)
                VStack(alignment: .leading, spacing: 20) {
                    // Date
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Date", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $noteDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    
                    // Category
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Category", systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Menu {
                            ForEach(NoteCategory.allCases, id: \.self) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    HStack {
                                        if category == cat { Image(systemName: "checkmark") }
                                        Text(cat.rawValue.capitalized)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(categoryColor(category))
                                    .frame(width: 8, height: 8)
                                Text(category.rawValue.capitalized)
                                    .font(.system(.body, design: .rounded))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .menuStyle(.borderlessButton)
                    }
                    
                    // Options
                    Toggle(isOn: $includeInReport) {
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
                
                // Right: Editor
                VStack(spacing: 0) {
                    // Selected Students Bar
                    if !selectedStudentIDs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(selectedStudentIDs), id: \.self) { id in
                                    if let student = students.first(where: { $0.id == id }) {
                                        QuickNoteStudentChip(student: student) {
                                            selectedStudentIDs.remove(id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 10)
                        }
                    }
                    
                    TextEditor(text: $bodyText)
                        .font(.system(size: 16, design: .default))
                        .lineSpacing(6)
                        .padding()
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .onChange(of: bodyText) { _, newValue in
                            analyzeText(newValue)
                        }
                    
                    // Bottom suggestions bar
                    if !detectedCandidateIDs.isEmpty {
                        HStack {
                            Text("Suggestions:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(detectedCandidateIDs), id: \.self) { id in
                                        if let student = students.first(where: { $0.id == id }) {
                                            Button {
                                                withAnimation {
                                                    selectedStudentIDs.insert(id)
                                                    detectedCandidateIDs.remove(id)
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "plus.circle.fill")
                                                    Text(student.firstName)
                                                }
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.1))
                                                .foregroundStyle(Color.accentColor)
                                                .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Attachment / Student Picker Bar
                    HStack {
                        Button {
                            isShowingStudentPicker = true
                        } label: {
                            Label("Add Student", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingStudentPicker) {
                            StudentPickerPopover(
                                students: students,
                                selectedIDs: $selectedStudentIDs,
                                onDone: { isShowingStudentPicker = false }
                            )
                        }
                        
                        Spacer()
                        
                        if let img = attachedImage {
                            HStack {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Button {
                                    attachedImage = nil
                                    attachedImagePath = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadPhoto(newItem)
        }
    }
    #endif

    // MARK: - iOS Layout
    #if !os(macOS)
    private var iOSLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Selected Students (Header)
                if !selectedStudentIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(selectedStudentIDs), id: \.self) { id in
                                if let student = students.first(where: { $0.id == id }) {
                                    QuickNoteStudentChip(student: student) {
                                        withAnimation { selectedStudentIDs.remove(id) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.3))
                    Divider()
                }
                
                // 2. Main Editor
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Write note here...")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                    }
                    
                    TextEditor(text: $bodyText)
                        .font(.system(.body, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.top, 8) // Adjustment for TextEditor padding quirks
                        .focused($isFocused)
                        .onChange(of: bodyText) { _, newValue in
                            analyzeText(newValue)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 3. Suggestions (Floating)
                if !detectedCandidateIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Suggested:")
                                .font(.caption2)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            
                            ForEach(Array(detectedCandidateIDs), id: \.self) { id in
                                if let student = students.first(where: { $0.id == id }) {
                                    Button {
                                        withAnimation {
                                            selectedStudentIDs.insert(id)
                                            detectedCandidateIDs.remove(id)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus")
                                                .font(.caption2.bold())
                                            Text(student.firstName)
                                                .font(.caption.weight(.medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Material.regular)
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color.clear)
                }
                
                Divider()
                
                // 4. Accessory Bar (Bear Style)
                HStack(spacing: 16) {
                    // Date
                    ZStack {
                        // Invisible DatePicker with icon overlay
                        DatePicker("", selection: $noteDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .colorMultiply(.clear) // Hide default text
                            .background(
                                Image(systemName: "calendar")
                                    .foregroundStyle(Calendar.current.isDateInToday(noteDate) ? .primary : .red)
                            )
                            .frame(width: 24, height: 24)
                            .fixedSize()
                    }
                    
                    // Category Menu
                    Menu {
                        ForEach(NoteCategory.allCases, id: \.self) { cat in
                            Button {
                                category = cat
                            } label: {
                                Label(cat.rawValue.capitalized, systemImage: category == cat ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Circle()
                            .fill(categoryColor(category))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    
                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 16)
                    
                    // Photo
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                    }
                    .foregroundStyle(.primary)
                    
                    Button {
                        isShowingCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 20))
                    }
                    .foregroundStyle(.primary)
                    
                    if attachedImage != nil {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }

                    Spacer()
                    
                    // Flag
                    Button {
                        includeInReport.toggle()
                    } label: {
                        Image(systemName: includeInReport ? "flag.fill" : "flag")
                            .foregroundStyle(includeInReport ? .orange : .secondary)
                            .font(.system(size: 20))
                    }
                    
                    // Add Student
                    Button {
                        isShowingStudentPicker = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(.accentColor)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .fontWeight(.bold)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .popover(isPresented: $isShowingStudentPicker) {
                StudentPickerPopover(
                    students: students,
                    selectedIDs: $selectedStudentIDs,
                    onDone: { isShowingStudentPicker = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraView(image: $attachedImage) { img in
                     if let img = img { processImage(img) }
                }
            }
        }
    }
    #endif

    // MARK: - Logic
    
    /// Breaks down text analysis to strict types to avoid "ambiguous expression" compiler errors
    private func analyzeText(_ text: String) {
        // Run on background to keep UI snappy
        Task.detached(priority: .userInitiated) {
            // Extract Sendable data from students to pass across actor boundary
            let studentData = await MainActor.run {
                students.map { student in
                    StudentMatchData(
                        id: student.id,
                        firstName: student.firstName,
                        lastName: student.lastName,
                        nickname: student.nickname
                    )
                }
            }
            
            let matches = await findStudentMatches(in: text, studentData: studentData)
            
            await MainActor.run {
                // Only suggest students not already selected
                self.detectedCandidateIDs = matches.subtracting(self.selectedStudentIDs)
            }
        }
    }
    
    /// Sendable struct for passing student data across actor boundaries
    private struct StudentMatchData: Sendable {
        let id: UUID
        let firstName: String
        let lastName: String
        let nickname: String?
    }
    
    /// Isolated logic function for NLP
    nonisolated private func findStudentMatches(in text: String, studentData: [StudentMatchData]) async -> Set<UUID> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        
        var matches = Set<UUID>()
        let range = text.startIndex..<text.endIndex
        
        // Use explicit closure type signature
        let handler: (NLTag?, Range<String.Index>) -> Bool = { tag, tokenRange in
            if tag == .personalName {
                let nameFound = String(text[tokenRange])
                // Simple fuzzy match logic
                for student in studentData {
                    if Self.isMatch(name: nameFound, student: student) {
                        matches.insert(student.id)
                    }
                }
            }
            return true
        }
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options, using: handler)
        
        return matches
    }
    
    /// Helper for string matching (static/nonisolated to be safe)
    nonisolated private static func isMatch(name: String, student: StudentMatchData) -> Bool {
        let needle = name.lowercased()
        let first = student.firstName.lowercased()
        let last = student.lastName.lowercased()
        let nick = (student.nickname ?? "").lowercased()
        
        // Exact First Name
        if needle == first { return true }
        // Exact Nickname
        if !nick.isEmpty && needle == nick { return true }
        // First Name + Last Initial (e.g. "Maria M")
        if needle.hasPrefix(first) && needle.contains(last.prefix(1)) { return true }
        // Full Name
        if needle.contains(first) && needle.contains(last) { return true }
        
        return false
    }

    private func saveNote() {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Determine scope
        let scope: NoteScope
        if selectedStudentIDs.count == 1 {
            scope = .student(selectedStudentIDs.first!)
        } else if selectedStudentIDs.count > 1 {
            scope = .students(Array(selectedStudentIDs))
        } else {
            scope = .all
        }
        
        // Create Note
        let newNote = Note(
            createdAt: noteDate, // Support backdating
            body: trimmed,
            scope: scope,
            category: category,
            includeInReport: includeInReport,
            imagePath: attachedImagePath
        )
        
        modelContext.insert(newNote)
        dismiss()
    }
    
    private func categoryColor(_ cat: NoteCategory) -> Color {
        switch cat {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .green
        case .general: return .gray
        }
    }
    
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let uiImage = PlatformImage(data: data) {
                    await MainActor.run {
                        processImage(uiImage)
                    }
                }
            }
        }
    }
    
    private func processImage(_ image: PlatformImage) {
        self.attachedImage = image
        // Save to disk
        do {
            self.attachedImagePath = try PhotoStorageService.saveImage(image)
        } catch {
            print("Failed to save image: \(error)")
        }
    }
}

// MARK: - Components

struct QuickNoteStudentChip: View {
    let student: Student
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            // Avatar placeholder
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 20, height: 20)
                .overlay {
                    Text(student.firstName.prefix(1))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            
            Text(student.firstName)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - iOS Camera Wrapper
#if !os(macOS)
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onCapture: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            parent.image = image
            parent.onCapture(image)
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
