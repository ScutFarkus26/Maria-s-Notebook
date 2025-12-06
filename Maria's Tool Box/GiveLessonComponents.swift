import SwiftUI
import SwiftData

// TODO: Consider moving formatting and selection helpers to GiveLessonViewModel for testability.

// MARK: - Lesson Section

struct LessonSection: View {
    @ObservedObject var viewModel: GiveLessonViewModel
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
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !isPresented { withAnimation(.easeInOut) { isPresented = true } }
                }
            }
            .onSubmit {
                // If the user typed an exact lesson name, select it
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = filteredLessons.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    selectedLessonID = match.id
                    searchText = match.name
                    withAnimation(.easeInOut) { isPresented = false }
                    isFocused = false
                }
            }
            .onChange(of: isFocused) { _, newValue in
                textFocused = newValue
                if newValue {
                    withAnimation(.easeInOut) { isPresented = true }
                }
            }
            .onChange(of: textFocused) { _, newValue in
                isFocused = newValue
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    DispatchQueue.main.async { textFocused = true }
                }
            }
            .onTapGesture {
                isFocused = true
                withAnimation(.easeInOut) { isPresented = true }
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
                    withAnimation(.easeInOut) { isPresented = false }
                    isFocused = false
                }) {
                    HStack {
                        Text(lessonDisplayTitle(lesson))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedLessonID == lesson.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
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
    @ObservedObject var viewModel: GiveLessonViewModel
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
                    GiveLessonStudentPickerPopover(
                        viewModel: viewModel,
                        displayName: displayName,
                        showingAddStudentSheet: $showingAddStudentSheet,
                        isPresented: $showingStudentPickerPopover
                    )
                    .padding(12)
                    .frame(minWidth: 320)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.selectedStudentIDs)
            
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
                        .foregroundColor(subjectColor)
                        .clipShape(Capsule())
                    Button {
                        onRemove(student.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(subjectColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }
}



// MARK: - Give Lesson Student Picker Popover

struct GiveLessonStudentPickerPopover: View {
    @ObservedObject var viewModel: GiveLessonViewModel
    let displayName: (Student) -> String
    @Binding var showingAddStudentSheet: Bool
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search students", text: $viewModel.studentSearchText)
                .textFieldStyle(.roundedBorder)
            
            Picker("Level", selection: $viewModel.studentLevelFilter) {
                ForEach(StudentLevelFilter.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            
            List(viewModel.filteredStudentsForPicker, id: \.id) { student in
                Button(action: {
                    viewModel.toggleStudentSelection(student.id)
                }) {
                    HStack {
                        Text(displayName(student))
                            .foregroundStyle(.primary)
                        Spacer()
                        if viewModel.selectedStudentIDs.contains(student.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minHeight: 200, maxHeight: 360)
            
            HStack {
                Button {
                    showingAddStudentSheet = true
                    isPresented = false
                } label: {
                    Label("Add Student", systemImage: "plus")
                }
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Status Section

struct StatusSection: View {
    @ObservedObject var viewModel: GiveLessonViewModel
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
                .animation(.easeInOut, value: viewModel.scheduledFor)
            } else {
                OptionalDatePicker(
                    toggleLabel: "Include date",
                    dateLabel: "Given At",
                    date: $viewModel.givenAt,
                    displayedComponents: [.date]
                )
                .animation(.easeInOut, value: viewModel.givenAt)
            }
        }
    }
}

// MARK: - Optional Date Picker

struct OptionalDatePicker: View {
    let toggleLabel: String
    let dateLabel: String
    @Binding var date: Date?
    let displayedComponents: DatePickerComponents
    let defaultHour: Int?
    @Environment(\.calendar) private var calendar
    
    init(
        toggleLabel: String,
        dateLabel: String,
        date: Binding<Date?>,
        displayedComponents: DatePickerComponents = [.date],
        defaultHour: Int? = nil
    ) {
        self.toggleLabel = toggleLabel
        self.dateLabel = dateLabel
        self._date = date
        self.displayedComponents = displayedComponents
        self.defaultHour = defaultHour
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(toggleLabel, isOn: Binding(
                get: { date != nil },
                set: { newValue in
                    if newValue {
                        if date == nil {
                            if let hour = defaultHour {
                                let base = calendar.startOfDay(for: Date())
                                date = calendar.date(byAdding: .hour, value: hour, to: base) ?? base
                            } else {
                                // Default to start of day when no default hour is provided
                                date = calendar.startOfDay(for: Date())
                            }
                        }
                    } else {
                        date = nil
                    }
                }
            ))
            if date != nil {
                DatePicker(
                    dateLabel,
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: displayedComponents
                )
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
            }
        }
    }
}



// MARK: - Give Lesson Notes Section

struct GiveLessonNotesSection: View {
    @Binding var notes: String
    @FocusState.Binding var focusedField: GiveLessonSheet.FocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .focused($focusedField, equals: .notes)
        }
    }
}

// MARK: - More Options Section

struct MoreOptionsSection: View {
    @ObservedObject var viewModel: GiveLessonViewModel
    let subjectColor: Color
    @Binding var showFollowUpField: Bool
    @FocusState.Binding var focusedField: GiveLessonSheet.FocusField?
    
    var body: some View {
        DisclosureGroup("More options") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TagChip(title: "Practice", isOn: $viewModel.needsPractice, color: subjectColor)
                    TagChip(title: "Re‑present", isOn: $viewModel.needsAnotherPresentation, color: subjectColor)
                }
                .padding(.vertical, 4)
                
                if showFollowUpField {
                    TextField("Add follow‑up…", text: $viewModel.followUpWork)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .followUp)
                } else {
                    Button("Add follow‑up…") {
                        showFollowUpField = true
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let title: String
    @Binding var isOn: Bool
    let color: Color
    
    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.2) : Color.secondary.opacity(0.12))
            .foregroundStyle(isOn ? color : .secondary)
            .overlay(
                Capsule().stroke(isOn ? color : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
            .onTapGesture {
                withAnimation(.easeInOut) { isOn.toggle() }
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

