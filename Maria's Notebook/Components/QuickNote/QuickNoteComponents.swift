import SwiftUI
import CoreData
import PhotosUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - CDStudent Chip

struct QuickNoteStudentChip: View {
    let student: CDStudent
    let displayName: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.moderate))
                .frame(width: 20, height: 20)
                .overlay {
                    Text(String(displayName.prefix(1)))
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
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
        .background(Color.secondary.opacity(UIConstants.OpacityConstants.light))
        .clipShape(Capsule())
    }
}

// MARK: - Selected Students Bar

struct SelectedStudentsBar: View {
    let students: [CDStudent]
    let selectedStudentIDs: Set<UUID>
    let displayName: (CDStudent) -> String
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
    let students: [CDStudent]
    let detectedCandidateIDs: Set<UUID>
    let displayName: (CDStudent) -> String
    let onAdd: (UUID) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Suggested:")
                    .font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
                
                ForEach(detectedCandidateIDs.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    if let student = students.first(where: { $0.id == id }) {
                        Button {
                            adaptiveWithAnimation {
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
                            .shadow(color: .black.opacity(UIConstants.OpacityConstants.light), radius: 2, y: 1)
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
                if let onFixGrammar {
                    Button(action: onFixGrammar) {
                        Label {
                            Text("Fix Grammar")
                        } icon: {
                            Image(systemName: "textformat.abc")
                        }
                    }
                }
                if let onProfessionalTone {
                    Button(action: onProfessionalTone) {
                        Label {
                            Text("Professional Tone")
                        } icon: {
                            Image(systemName: "briefcase")
                        }
                    }
                }
                if let onExpandNote {
                    Button(action: onExpandNote) {
                        Label {
                            Text("Expand CDNote")
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

// MARK: - Quick CDNote Editor

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
                .font(AppTheme.ScaledFont.callout)
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

// MARK: - CDLesson Picker

struct QuickNoteLessonPicker: View {
    @Binding var selectedLessonID: UUID?
    var onDone: (() -> Void)?

    @State private var searchText: String = ""
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]) private var lessons: FetchedResults<CDLesson>
    @Environment(\.dismiss) private var dismiss

    private var filteredLessons: [CDLesson] {
        if searchText.trimmed().isEmpty { return Array(lessons) }
        let query = searchText.trimmed()
        return lessons.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.subject.localizedCaseInsensitiveContains(query) ||
            $0.group.localizedCaseInsensitiveContains(query)
        }
    }

    private func done() {
        if let onDone { onDone() } else { dismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search lessons...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: SFSymbol.Action.xmarkCircleFill)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            List {
                // "None" option to clear
                Button {
                    adaptiveWithAnimation { selectedLessonID = nil }
                    done()
                } label: {
                    HStack {
                        Text("None").foregroundStyle(.secondary)
                        Spacer()
                        if selectedLessonID == nil {
                            Image(systemName: SFSymbol.Action.checkmark)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filteredLessons) { lesson in
                    Button {
                        adaptiveWithAnimation { selectedLessonID = lesson.id }
                        done()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.name.isEmpty ? "Untitled CDLesson" : lesson.name)
                                    .foregroundStyle(.primary)
                                let subtitle = [lesson.subject, lesson.group]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " \u{00B7} ")
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedLessonID == lesson.id {
                                Image(systemName: SFSymbol.Action.checkmark)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 300)
        #endif
    }
}
