import SwiftUI
import SwiftData
import Combine

// WorkDetailViewModel is defined in WorkDetailViewModel.swift

struct WorkDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessons: [StudentLesson]

    @StateObject private var vm: WorkDetailViewModel
    
    @State private var checkInDate: Date = Date()
    @State private var checkInPurpose: String = ""
    @State private var editingCheckInNote: WorkCheckIn? = nil
    @State private var noteText: String = ""

    let work: WorkModel
    var onDone: (() -> Void)? = nil

    init(work: WorkModel, onDone: (() -> Void)? = nil) {
        self.work = work
        self.onDone = onDone
        _vm = StateObject(wrappedValue: WorkDetailViewModel(work: work, onDone: onDone))
    }

    private static let createdDateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private static let createdDateOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    private var subject: String {
        if let slID = vm.selectedStudentLessonID,
           let snap = vm.studentLessonSnapshotsByID[slID],
           let lesson = vm.lessonsByID[snap.lessonID] {
            return lesson.subject
        }
        return ""
    }

    private var subjectColor: Color {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .accentColor : AppColors.color(forSubject: subject)
    }

    private var chipBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var separatorStrokeColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.12)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    private func displayName(for student: Student) -> String {
        selectedStudentsList.first(where: { $0.id == student.id }).map { s in
            let f = s.firstName
            let l = s.lastName
            if !f.isEmpty && !l.isEmpty {
                return "\(f) \(l.prefix(1))."
            }
            return f + (l.isEmpty ? "" : " \(l)")
        } ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1) Title at the top
                    TextField("Title", text: $vm.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .heavy, design: .rounded))
                        .padding(.top, 14)

                    // 2) Students directly under title
                    StudentsChipsRow(students: studentsAll, selectedIDs: $vm.selectedStudentIDs, subjectColor: subjectColor) {
                        showingStudentPickerPopover = true
                    }

                    // 3) Linked Lesson next, with 4) Work Type beside if space allows
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            LinkedLessonSection(
                                lessonsByID: vm.lessonsByID,
                                studentLessonSnapshotsByID: vm.studentLessonSnapshotsByID,
                                selectedStudentLessonID: $vm.selectedStudentLessonID,
                                createdDateOnlyFormatter: Self.createdDateOnlyFormatter,
                                onOpenLinkedDetails: { showingLinkedLessonDetails = true },
                                onOpenBaseLesson: { showingBaseLessonDetails = true }
                            )
                            WorkTypePickerSection(workType: $vm.workType)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            LinkedLessonSection(
                                lessonsByID: vm.lessonsByID,
                                studentLessonSnapshotsByID: vm.studentLessonSnapshotsByID,
                                selectedStudentLessonID: $vm.selectedStudentLessonID,
                                createdDateOnlyFormatter: Self.createdDateOnlyFormatter,
                                onOpenLinkedDetails: { showingLinkedLessonDetails = true },
                                onOpenBaseLesson: { showingBaseLessonDetails = true }
                            )
                            WorkTypePickerSection(workType: $vm.workType)
                        }
                    }

                    // 5) Per-Student Completion
                    perStudentCompletionSection

                    // 6) Notes
                    NotesSection(notes: $vm.notes, separatorStrokeColor: separatorStrokeColor)

                    // 7) Scheduled Check-Ins List
                    scheduledCheckInsSection

                    // 8) Schedule New Check-In
                    checkInSection

                    // 9) Created / meta row retained for context
                    metaRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .onAppear {
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: lessons.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: studentsAll.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
                .onChange(of: studentLessons.map(\.id)) { _, _ in
                    vm.rebuildCaches(lessons: lessons, students: studentsAll, studentLessons: studentLessons)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .background(.ultraThinMaterial)
                .padding(.top, 6)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .alert("Delete Work?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                vm.deleteWork(modelContext: modelContext) {
                    if let onDone = onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingLinkedLessonDetails) {
            if let slID = vm.selectedStudentLessonID, let sl = vm.studentLessonsByID[slID] {
                StudentLessonDetailView(studentLesson: sl) { showingLinkedLessonDetails = false }
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .padding(.bottom, 16)
#endif
            } else { EmptyView() }
        }
        .sheet(isPresented: $showingBaseLessonDetails) {
            if let slID = vm.selectedStudentLessonID,
               let sl = vm.studentLessonsByID[slID],
               let lesson = vm.lessonsByID[sl.lessonID] {
                LessonDetailView(lesson: lesson, onSave: { _ in
                    do { try modelContext.save() } catch { }
                }, onDone: { showingBaseLessonDetails = false })
#if os(macOS)
                .frame(minWidth: 520, minHeight: 560)
                .presentationSizing(.fitted)
#else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .padding(.bottom, 16)
#endif
            } else { EmptyView() }
        }
        .popover(isPresented: $showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(students: studentsAll, selectedIDs: $vm.selectedStudentIDs) {
                showingStudentPickerPopover = false
            }
        }
        .sheet(item: $editingCheckInNote) { checkIn in
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Note")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(checkIn.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        
                        let purposeText = checkIn.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !purposeText.isEmpty {
                            Text("|")
                                .foregroundStyle(.secondary)
                            Text(purposeText)
                                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                
                Divider()
                
#if os(macOS)
                TextEditor(text: $noteText)
                    .font(.system(size: AppTheme.FontSize.body))
                    .frame(minHeight: 120)
                    .border(Color.primary.opacity(0.2), width: 1)
#else
                TextEditor(text: $noteText)
                    .font(.system(size: AppTheme.FontSize.body))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(8)
#endif
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        editingCheckInNote = nil
                        noteText = ""
                    }
                    Button("Save") {
                        vm.updateCheckInNote(checkIn.id, note: noteText)
                        editingCheckInNote = nil
                        noteText = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
#if os(macOS)
            .frame(minWidth: 440, minHeight: 320)
            .presentationSizing(.fitted)
#else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
        }
    }

    @State private var showDeleteAlert = false
    @State private var showingStudentPickerPopover = false
    @State private var showingLinkedLessonDetails = false
    @State private var showingBaseLessonDetails = false

    private var perStudentCompletionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "person.2", title: "Per-Student Completion")
            if selectedStudentsList.isEmpty {
                Text("No students selected for this work.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedStudentsList, id: \.id) { student in
                        Toggle(isOn: Binding(
                            get: { vm.isStudentCompletedDraft(student.id) },
                            set: { vm.setStudentCompletedDraft(student.id, $0) }
                        )) {
                            Text(displayName(for: student))
                        }
                    }
                }
            }
        }
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "calendar.badge.clock", title: "Schedule Check-In")
            
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: $checkInDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                
                TextField("Purpose (optional)", text: $checkInPurpose)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    vm.addCheckInDraft(date: checkInDate, purpose: checkInPurpose, note: "", modelContext: modelContext)
                    checkInPurpose = ""
                    checkInDate = Date()
                } label: {
                    Label("Schedule Check-In", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var scheduledCheckInsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "checklist", title: "Scheduled Check-Ins")
            
            let scheduledCheckIns = vm.checkIns.sorted(by: { $0.date < $1.date })
            
            if scheduledCheckIns.isEmpty {
                Text("No check-ins scheduled yet.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: AppTheme.FontSize.body))
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scheduledCheckIns, id: \.id) { checkIn in
                        HStack(alignment: .top, spacing: 10) {
                            // Status icon
                            Image(systemName: checkIn.status == .completed ? "checkmark.circle.fill" : (checkIn.status == .skipped ? "xmark.circle.fill" : "clock"))
                                .foregroundStyle(checkIn.status == .completed ? .green : (checkIn.status == .skipped ? .red : .orange))
                                .font(.system(size: 18))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(checkIn.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                    
                                    let purposeText = checkIn.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !purposeText.isEmpty {
                                        Text("|")
                                            .foregroundStyle(.secondary)
                                        Text(purposeText)
                                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                                    }
                                }
                                
                                if !checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("Notes:")
                                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Text(checkIn.note)
                                            .font(.system(size: AppTheme.FontSize.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            
                            Spacer()
                            
                            Menu {
                                Button {
                                    noteText = checkIn.note
                                    editingCheckInNote = checkIn
                                } label: {
                                    Label("Add/Edit Note", systemImage: "note.text")
                                }
                                
                                Divider()
                                
                                Button {
                                    vm.setCheckInDraftStatus(checkIn.id, to: .completed)
                                } label: {
                                    Label("Mark Completed", systemImage: "checkmark.circle")
                                }
                                
                                Button {
                                    vm.setCheckInDraftStatus(checkIn.id, to: .scheduled)
                                } label: {
                                    Label("Mark Scheduled", systemImage: "clock")
                                }
                                
                                Button {
                                    vm.setCheckInDraftStatus(checkIn.id, to: .skipped)
                                } label: {
                                    Label("Mark Skipped", systemImage: "xmark.circle")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    vm.deleteCheckInDraft(checkIn, modelContext: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: AppTheme.FontSize.caption))
            }

            Spacer()

            Button("Cancel") {
                if let onDone = onDone {
                    onDone()
                } else {
                    dismiss()
                }
            }
            .font(.system(size: AppTheme.FontSize.caption))

            Button("Save") {
                vm.save(modelContext: modelContext) {
                    if let onDone = onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: AppTheme.FontSize.caption))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.vertical, 8)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text("Created:")
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.secondary)
            Text(Self.createdDateTimeFormatter.string(from: work.createdAt))
                .font(.system(size: AppTheme.FontSize.caption))
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

