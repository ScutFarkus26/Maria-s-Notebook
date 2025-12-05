import SwiftUI
import SwiftData

struct AttendanceView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)])
    private var allStudents: [Student]

    @StateObject private var viewModel = AttendanceViewModel()

    private var filteredStudents: [Student] {
        let visible = viewModel.visibleStudents(from: allStudents)
        return viewModel.sortedAndFiltered(students: visible)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]
    }

    private var isNonSchoolDay: Bool {
        SchoolCalendar.isNonSchoolDay(viewModel.selectedDate, using: modelContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            viewModel.load(for: viewModel.selectedDate, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
        }
        .onChange(of: viewModel.selectedDate) { _, newValue in
            viewModel.load(for: newValue, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
        }
        .onChange(of: allStudents.map { $0.id }) { _, _ in
            // If students change (added/removed), ensure records exist
            viewModel.load(for: viewModel.selectedDate, students: viewModel.visibleStudents(from: allStudents), modelContext: modelContext)
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) {
                        viewModel.selectedDate = newDate.normalizedDay()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Previous Day")

                DatePicker("Date", selection: Binding(get: { viewModel.selectedDate }, set: { viewModel.selectedDate = $0.normalizedDay() }), displayedComponents: .date)
#if os(macOS)
                    .datePickerStyle(.field)
#else
                    .datePickerStyle(.compact)
#endif

                Button {
                    if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.selectedDate) {
                        viewModel.selectedDate = newDate.normalizedDay()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("Next Day")

                Spacer()

                // Level filter
                Picker("Level", selection: $viewModel.levelFilter) {
                    Text("All").tag(AttendanceViewModel.LevelFilter.all)
                    Text("Lower").tag(AttendanceViewModel.LevelFilter.lower)
                    Text("Upper").tag(AttendanceViewModel.LevelFilter.upper)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                // Sort picker
                Picker("Sort", selection: $viewModel.sortKey) {
                    Text("First").tag(AttendanceViewModel.SortKey.firstName)
                    Text("Last").tag(AttendanceViewModel.SortKey.lastName)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            if isNonSchoolDay {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Marked as a non-school day. Attendance is optional; bulk actions disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }

            // Header stats: "In Class" treats Present + Tardy as in-class attendance.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Primary stat: In Class
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("In Class")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.inClassCount)")
                            .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                    }
                    Text("Present + Tardy")
                        .font(.system(size: AppTheme.FontSize.captionSmall, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 4)

                // Breakdown chips (secondary)
                HStack(spacing: 8) {
                    breakdownChip(title: "Present", count: viewModel.countPresent, color: .green)
                    breakdownChip(title: "Tardy", count: viewModel.countTardy, color: .blue)
                    breakdownChip(title: "Absent", count: viewModel.countAbsent, color: .red)
                    breakdownChip(title: "Left Early", count: viewModel.countLeftEarly, color: .purple)
                    breakdownChip(title: "Unmarked", count: viewModel.countUnmarked, color: .gray)
                }

                Spacer()

                Button("Mark All Present") {
                    viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNonSchoolDay)
#if os(macOS)
                .keyboardShortcut("p", modifiers: [.command, .shift])
#endif

                Button("Reset Day") {
                    viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                }
                .buttonStyle(.bordered)
                .disabled(isNonSchoolDay)
#if os(macOS)
                .keyboardShortcut("r", modifiers: [.command, .shift])
#endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statChip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(value)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
    }

    private func breakdownChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Content
    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(filteredStudents, id: \.id) { student in
                    AttendanceCard(student: student, record: viewModel.recordsByStudent[student.id]) {
                        viewModel.cycleStatus(for: student, modelContext: modelContext)
                    } onEditNote: { newNote in
                        viewModel.updateNote(for: student, note: newNote, modelContext: modelContext)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Card View
private struct AttendanceCard: View {
    let student: Student
    let record: AttendanceRecord?
    let onTap: () -> Void
    let onEditNote: (String?) -> Void

    @State private var showingNoteEditor = false
    @State private var draftNote: String = ""

    private var status: AttendanceStatus { record?.status ?? .unmarked }

    private var statusLabel: String { status.displayName }

    private var accentColor: Color {
        switch status {
        case .present: return .green
        case .tardy: return .blue
        case .absent: return .red
        case .leftEarly: return .purple
        case .unmarked: return .gray.opacity(0.4)
        }
    }

    private var hasNote: Bool {
        let t = record?.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty
    }

    private var background: some View {
        // Neutral card background with subtle elevation
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar indicating status color
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(student.fullName)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    // Small note icon at far right (only when no note exists)
                    if !hasNote {
                        Button {
                            draftNote = record?.note ?? ""
                            showingNoteEditor = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .imageScale(.medium)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Add Note")
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Compact status pill
                Text(statusLabel)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(accentColor.opacity(0.12))
                    )

                // Clicking the note opens the editor
                if hasNote {
                    Button {
                        draftNote = record?.note ?? ""
                        showingNoteEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                            Text(record?.note ?? "")
                                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Edit note")
                }
            }
            .padding(10)
        }
        .frame(minHeight: 88)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { onTap() })
#else
        .onTapGesture { onTap() }
#endif
        .contextMenu {
            Button {
                draftNote = record?.note ?? ""
                showingNoteEditor = true
            } label: {
                Label("Note…", systemImage: "square.and.pencil")
            }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NoteEditorSheet(initialNote: record?.note ?? "") { newNote in
                onEditNote(newNote)
                showingNoteEditor = false
            } onCancel: {
                showingNoteEditor = false
            }
#if os(macOS)
            .frame(minWidth: 420, minHeight: 220)
            .presentationSizing(.fitted)
#endif
        }
    }
}

// MARK: - Note Editor
private struct NoteEditorSheet: View {
    @State private var text: String
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    init(initialNote: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialNote)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Note")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
            TextField("Optional note", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

#Preview {
    AttendanceView()
}

