import SwiftUI
import SwiftData

struct AttendanceView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)])
    private var allStudents: [Student]

    @StateObject private var viewModel = AttendanceViewModel()

    private var filteredStudents: [Student] {
        let base: [Student]
        switch viewModel.levelFilter {
        case .all: base = allStudents
        case .lower: base = allStudents.filter { $0.level == .lower }
        case .upper: base = allStudents.filter { $0.level == .upper }
        }
        let sorted: [Student]
        switch viewModel.sortKey {
        case .firstName:
            sorted = base.sorted { lhs, rhs in
                let c = lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName)
                if c == .orderedSame {
                    return lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName) == .orderedAscending
                }
                return c == .orderedAscending
            }
        case .lastName:
            sorted = base.sorted { lhs, rhs in
                let c = lhs.lastName.localizedCaseInsensitiveCompare(rhs.lastName)
                if c == .orderedSame {
                    return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
                }
                return c == .orderedAscending
            }
        }
        return sorted
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear {
            viewModel.load(for: viewModel.selectedDate, students: allStudents, modelContext: modelContext)
        }
        .onChange(of: viewModel.selectedDate) { _, newValue in
            viewModel.load(for: newValue, students: allStudents, modelContext: modelContext)
        }
        .onChange(of: allStudents.map { $0.id }) { _, _ in
            // If students change (added/removed), ensure records exist
            viewModel.load(for: viewModel.selectedDate, students: allStudents, modelContext: modelContext)
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

            // Quick stats
            HStack(spacing: 12) {
                statChip(label: "P", value: viewModel.countPresent, color: .green)
                statChip(label: "A", value: viewModel.countAbsent, color: .red)
                statChip(label: "T", value: viewModel.countTardy, color: .blue)
                statChip(label: "L", value: viewModel.countLeftEarly, color: .purple)
                statChip(label: "U", value: viewModel.countUnmarked, color: .gray)
                Spacer()
                Button("Mark All Present") {
                    viewModel.markAllPresent(students: filteredStudents, modelContext: modelContext)
                }
                .buttonStyle(.borderedProminent)
#if os(macOS)
                .keyboardShortcut("p", modifiers: [.command, .shift])
#endif
                Button("Reset Day") {
                    viewModel.resetDay(students: filteredStudents, modelContext: modelContext)
                }
                .buttonStyle(.bordered)
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

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(status.color)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(student.fullName)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }

            if let note = record?.note, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text").foregroundStyle(.secondary)
                    Text(note).font(.system(size: AppTheme.FontSize.caption, design: .rounded)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                statusBadge
                Spacer()
                Button {
                    draftNote = record?.note ?? ""
                    showingNoteEditor = true
                } label: {
                    Label("Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Note")
            }
        }
        .padding(10)
        .frame(minHeight: 88)
        .background(background)
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

    private var statusBadge: some View {
        Button(action: onTap) {
            Text(statusLabel)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(status.color.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .help("Advance status")
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

