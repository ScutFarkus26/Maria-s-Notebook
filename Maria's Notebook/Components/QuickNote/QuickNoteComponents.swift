import SwiftUI
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Student Chip

struct QuickNoteStudentChip: View {
    let student: Student
    let displayName: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 20, height: 20)
                .overlay {
                    Text(String(displayName.prefix(1)))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            
            Text(displayName)
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

// MARK: - Selected Students Bar

struct SelectedStudentsBar: View {
    let students: [Student]
    let selectedStudentIDs: Set<UUID>
    let displayName: (Student) -> String
    let onRemove: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedStudentIDs.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    if let student = students.first(where: { $0.id == id }) {
                        QuickNoteStudentChip(
                            student: student,
                            displayName: displayName(student)
                        ) {
                            onRemove(id)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Suggestions Bar

struct SuggestionsBar: View {
    let students: [Student]
    let detectedCandidateIDs: Set<UUID>
    let displayName: (Student) -> String
    let onAdd: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Suggested:")
                    .font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
                
                ForEach(detectedCandidateIDs.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    if let student = students.first(where: { $0.id == id }) {
                        Button {
                            withAnimation {
                                onAdd(id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus").font(.caption2.bold())
                                Text(displayName(student)).font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Material.regular)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - AI Menu Button

struct QuickNoteAIMenuButton: View {
    let onFormatNames: () -> Void
    #if ENABLE_FOUNDATION_MODELS
    let onFixGrammar: (() -> Void)?
    let onProfessionalTone: (() -> Void)?
    let onExpandNote: (() -> Void)?
    
    init(
        onFormatNames: @escaping () -> Void,
        onFixGrammar: (() -> Void)? = nil,
        onProfessionalTone: (() -> Void)? = nil,
        onExpandNote: (() -> Void)? = nil
    ) {
        self.onFormatNames = onFormatNames
        self.onFixGrammar = onFixGrammar
        self.onProfessionalTone = onProfessionalTone
        self.onExpandNote = onExpandNote
    }
    #else
    init(onFormatNames: @escaping () -> Void) {
        self.onFormatNames = onFormatNames
    }
    #endif
    
    var body: some View {
        Menu {
            Section("Writing Tools") {
                #if ENABLE_FOUNDATION_MODELS
                if let onFixGrammar = onFixGrammar {
                    Button(action: onFixGrammar) {
                        Label {
                            Text("Fix Grammar")
                        } icon: {
                            Image(systemName: "textformat.abc")
                        }
                    }
                }
                if let onProfessionalTone = onProfessionalTone {
                    Button(action: onProfessionalTone) {
                        Label {
                            Text("Professional Tone")
                        } icon: {
                            Image(systemName: "briefcase")
                        }
                    }
                }
                if let onExpandNote = onExpandNote {
                    Button(action: onExpandNote) {
                        Label {
                            Text("Expand Note")
                        } icon: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }
                #endif
                
                // Logic-Based (Not AI) - Always Available and Deterministic
                Button(action: onFormatNames) {
                    Label {
                        Text("Format Names (Maria G.)")
                    } icon: {
                        Image(systemName: "person.text.rectangle")
                    }
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse)
                .font(.system(size: 20))
                .foregroundStyle(.purple)
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Attachment Thumbnail (macOS)

#if os(macOS)
struct QuickNoteAttachmentThumbnail: View {
    let image: PlatformImage
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(nsImage: image as NSImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
#endif

// MARK: - Quick Note Editor

struct QuickNoteEditor: View {
    @Binding var bodyText: String
    @FocusState.Binding var isFocused: Bool
    let isProcessingAI: Bool
    let onTextChange: (String) -> Void
    
    #if !os(macOS)
    var placeholder: String = "Write note here..."
    #endif
    
    var body: some View {
        #if os(macOS)
        macOSEditor
        #else
        iOSEditor
        #endif
    }
    
    #if os(macOS)
    private var macOSEditor: some View {
        ZStack(alignment: .topTrailing) {
            TextEditor(text: $bodyText)
                .font(.system(size: 16, design: .default))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding()
                .focused($isFocused)
                .onChange(of: bodyText) { _, newValue in onTextChange(newValue) }
                .disabled(isProcessingAI)
                .opacity(isProcessingAI ? 0.6 : 1)
            
            if isProcessingAI {
                ProgressView()
                    .padding()
            }
        }
    }
    #else
    private var iOSEditor: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty && !isProcessingAI {
                Text(placeholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .focused($isFocused)
                .onChange(of: bodyText) { _, newValue in onTextChange(newValue) }
                .disabled(isProcessingAI)
                .opacity(isProcessingAI ? 0.6 : 1)
            
            if isProcessingAI {
                Center {
                    VStack {
                        ProgressView()
                        Text("Refining...").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
    }
    #endif
}

// MARK: - Helper Views

struct Center<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack { Spacer(); HStack { Spacer(); content; Spacer() }; Spacer() }
    }
}

// MARK: - Camera View (iOS only)

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
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif

