import SwiftUI
import SwiftData

// MARK: - Lesson Section

struct LessonSection: View {
    @Bindable var viewModel: LessonPickerViewModel
    let resolvedLesson: Lesson?
    let lessonDisplayTitle: (Lesson) -> String
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

// MARK: - Lesson Search Field

struct LessonSearchField: View {
    @Binding var searchText: String
    let filteredLessons: [Lesson]
    @Binding var selectedLessonID: UUID?
    let lessonDisplayTitle: (Lesson) -> String
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
                if let match = filteredLessons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
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

// MARK: - Lesson Picker Popover

struct LessonPickerPopover: View {
    let filteredLessons: [Lesson]
    @Binding var selectedLessonID: UUID?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    let lessonDisplayTitle: (Lesson) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(filteredLessons, id: \.id) { lesson in
                Button(action: {
                    selectedLessonID = lesson.id
                    searchText = lesson.name
                    adaptiveWithAnimation(.easeInOut) { isPresented = false }
                    isFocused = false
                }) {
                    HStack {
                        Text(lessonDisplayTitle(lesson))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
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

// MARK: - Students Section

struct StudentsSection: View {
    @Bindable var viewModel: LessonPickerViewModel
    let subjectColor: Color
    let displayName: (Student) -> String
    @Binding var showingAddStudentSheet: Bool
    @Binding var showingStudentPickerPopover: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who")
                .font(.headline)
            
            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    StudentChipsList(
                        students: viewModel.selectedStudents,
                        subjectColor: subjectColor,
                        displayName: displayName,
                        onRemove: viewModel.removeStudent
                    )
                    .padding(.vertical, 2)
                }
                
                Button {
                    showingStudentPickerPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(subjectColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .bottom) {
                    StudentPickerPopover(
                        students: viewModel.sortedStudents,
                        selectedIDs: $viewModel.selectedStudentIDs,
                        onDone: { showingStudentPickerPopover = false }
                    )
                    .padding(12)
                    .frame(minWidth: 320)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .adaptiveAnimation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.selectedStudentIDs)
            
            if viewModel.selectedStudentIDs.isEmpty {
                Text("Add at least one student.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            if viewModel.shouldShowScheduleHint {
                Text("Without a date, this plan appears in Ready to Schedule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Student Chips List

struct StudentChipsList: View {
    let students: [Student]
    let subjectColor: Color
    let displayName: (Student) -> String
    let onRemove: (UUID) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(students, id: \.id) { student in
                HStack(spacing: 4) {
                    Text(displayName(student))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(subjectColor.opacity(0.2))
                        .foregroundStyle(subjectColor)
                        .clipShape(Capsule())
                    Button {
                        onRemove(student.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(subjectColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }
}



// MARK: - Status Section

struct StatusSection: View {
    @Bindable var viewModel: LessonPickerViewModel
    let subjectColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status").font(.headline)
            
            HStack {
                Button(action: viewModel.toggleMode) {
                    Text(viewModel.mode == .plan ? "Plan" : "Given")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(subjectColor.opacity(0.2))
                        .foregroundStyle(subjectColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Spacer()
            }
            
            if viewModel.mode == .plan {
                OptionalDatePicker(
                    toggleLabel: "Schedule",
                    dateLabel: "Schedule For",
                    date: $viewModel.scheduledFor,
                    displayedComponents: [.date, .hourAndMinute],
                    defaultHour: 9
                )
                .adaptiveAnimation(.easeInOut, value: viewModel.scheduledFor)
            } else {
                OptionalDatePicker(
                    toggleLabel: "Include date",
                    dateLabel: "Given At",
                    date: $viewModel.givenAt,
                    displayedComponents: [.date]
                )
                .adaptiveAnimation(.easeInOut, value: viewModel.givenAt)
            }
        }
    }
}



// MARK: - Keyboard Shortcuts Overlay

struct KeyboardShortcutsOverlay: View {
    let focusLesson: () -> Void
    let openStudents: () -> Void
    let focusNotes: () -> Void
    let toggleStatus: () -> Void
    
    var body: some View {
        ZStack {
            Button(action: focusLesson) { EmptyView() }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: openStudents) { EmptyView() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: focusNotes) { EmptyView() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .opacity(0.001)
                .accessibilityHidden(true)
            Button(action: toggleStatus) { EmptyView() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .opacity(0.001)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}

