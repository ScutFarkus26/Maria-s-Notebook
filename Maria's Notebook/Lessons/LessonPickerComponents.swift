import SwiftUI
import CoreData

// MARK: - CDLesson Section

struct LessonSection: View {
    @Bindable var viewModel: LessonPickerViewModel
    let resolvedLesson: CDLesson?
    let lessonDisplayTitle: (CDLesson) -> String
    @Binding var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lesson")
                .font(.headline)
            
            LessonSearchField(
                searchText: $viewModel.lessonSearchText,
                filteredLessons: viewModel.filteredLessons,
                selectedLessonID: $viewModel.selectedLessonID,
                lessonDisplayTitle: lessonDisplayTitle,
                isFocused: $isFocused
            )
            
            if let lesson = resolvedLesson {
                Text(lessonDisplayTitle(lesson))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose a lesson to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - CDLesson Search Field

struct LessonSearchField: View {
    @Binding var searchText: String
    let filteredLessons: [CDLesson]
    @Binding var selectedLessonID: UUID?
    let lessonDisplayTitle: (CDLesson) -> String
    @Binding var isFocused: Bool
    
    @FocusState private var textFocused: Bool
    @State private var isPresented: Bool = false
    
    var body: some View {
        TextField("What lesson?", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($textFocused)
            .onChange(of: searchText) { _, newValue in
                // Keep the popover visible while typing
                if !newValue.trimmed().isEmpty {
                    if !isPresented { adaptiveWithAnimation(.easeInOut) { isPresented = true } }
                }
            }
            .onSubmit {
                // If the user typed an exact lesson name, select it
                let trimmed = searchText.trimmed()
                let match = filteredLessons.first {
                    $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                }
                if let match {
                    selectedLessonID = match.id
                    searchText = match.name
                    adaptiveWithAnimation(.easeInOut) { isPresented = false }
                    isFocused = false
                }
            }
            .onChange(of: isFocused) { _, newValue in
                textFocused = newValue
                if newValue {
                    adaptiveWithAnimation(.easeInOut) { isPresented = true }
                }
            }
            .onChange(of: textFocused) { _, newValue in
                isFocused = newValue
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    Task { @MainActor in
                        textFocused = true
                    }
                }
            }
            .onTapGesture {
                isFocused = true
                adaptiveWithAnimation(.easeInOut) { isPresented = true }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                LessonPickerPopover(
                    filteredLessons: filteredLessons,
                    selectedLessonID: $selectedLessonID,
                    searchText: $searchText,
                    isPresented: $isPresented,
                    isFocused: $isFocused,
                    lessonDisplayTitle: lessonDisplayTitle
                )
            }
    }
}

// MARK: - CDLesson Picker Popover

struct LessonPickerPopover: View {
    let filteredLessons: [CDLesson]
    @Binding var selectedLessonID: UUID?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    let lessonDisplayTitle: (CDLesson) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons, id: \.id) { lesson in
                Button(action: {
                    selectedLessonID = lesson.id
                    searchText = lesson.name
                    adaptiveWithAnimation(.easeInOut) { isPresented = false }
                    isFocused = false
                }, label: {
                    HStack {
                        Text(lessonDisplayTitle(lesson))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                })
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            #if os(macOS)
            .focusable(false)
            #endif
        }
        .padding(8)
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #endif
    }
}
