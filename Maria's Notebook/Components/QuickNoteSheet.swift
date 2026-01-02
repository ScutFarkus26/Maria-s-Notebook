import SwiftUI
import SwiftData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

struct QuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: [
        SortDescriptor(\Student.firstName),
        SortDescriptor(\Student.lastName)
    ]) private var students: [Student]
    
    let initialStudentID: UUID?
    
    @State private var selectedStudentID: UUID? = nil
    
    init(initialStudentID: UUID? = nil) {
        self.initialStudentID = initialStudentID
    }
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
    
    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            headerView
            mainContentCard
            actionButtons
        }
        .padding(24)
        .frame(width: 480, height: 560)
        .onAppear {
            if let initialID = initialStudentID {
                selectedStudentID = initialID
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            handlePhotoChange(newItem)
        }
        #else
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mainContentCard
                }
                .padding(24)
            }
            .navigationTitle("Quick Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
        .onAppear {
            if let initialID = initialStudentID {
                selectedStudentID = initialID
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            handlePhotoChange(newItem)
        }
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
    
    private var headerView: some View {
        HStack {
            Text("Quick Note")
                .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
            Spacer()
        }
    }
    
    private var mainContentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            studentSelectionSection
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
    
    private var studentSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Student")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            studentPickerButton
        }
    }
    
    private var studentPickerButton: some View {
        Button {
            showingStudentPicker = true
        } label: {
            HStack {
                studentDisplayText
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingStudentPicker, arrowEdge: .top) {
            studentPickerPopover
        }
    }
    
    private var studentDisplayText: some View {
        Group {
            if let studentID = selectedStudentID,
               let student = students.first(where: { $0.id == studentID }) {
                Text(StudentFormatter.displayName(for: student))
                    .foregroundStyle(.primary)
            } else {
                Text("Select student...")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var studentPickerPopover: some View {
        StudentPickerPopover(
            students: students,
            selectedIDs: Binding(
                get: {
                    if let id = selectedStudentID {
                        return [id]
                    }
                    return []
                },
                set: { newValue in
                    selectedStudentID = newValue.first
                }
            ),
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
        selectedStudentID != nil && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func handlePhotoChange(_ newItem: PhotosPickerItem?) {
        Task {
            if let newItem = newItem {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    #if os(macOS)
                    if let image = NSImage(data: data) {
                        selectedImage = image
                        // Save the image and get the filename
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
        // Save the image and get the filename
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
    
    private func saveNote() {
        guard let studentID = selectedStudentID else { return }
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        
        let scope: NoteScope = .student(studentID)
        let note = Note(
            body: trimmedBody,
            scope: scope,
            category: category,
            includeInReport: includeInReport,
            imagePath: imagePath
        )
        
        modelContext.insert(note)
        dismiss()
    }
}

#Preview {
    QuickNoteSheet()
        .previewEnvironment()
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

