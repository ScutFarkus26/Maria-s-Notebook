import SwiftUI
import CoreData
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import QuickLookUI
#endif

struct TodoEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]) var studentsRaw: FetchedResults<CDStudent>
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(studentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    let todo: CDTodoItem
    let onDone: (() -> Void)?

    @State var title: String
    @State var notes: String
    @State var selectedStudentIDs: Set<String>
    @State var isSuggestingStudents = false
    @State var hasDueDate: Bool
    @State var dueDate: Date
    @State var scheduledDate: Date?
    @State var deadlineDate: Date?
    @State var isSomeday: Bool
    @State var repeatAfterCompletion: Bool
    @State var customIntervalDays: Int
    @State var priority: TodoPriority
    @State var recurrence: RecurrencePattern
    @State var estimatedHours: Int
    @State var estimatedMinutes: Int
    @State var actualHours: Int
    @State var actualMinutes: Int
    @State var hasReminder: Bool
    @State var reminderDate: Date
    @State var isSchedulingNotification = false
    @State var showingSaveAsTemplate = false
    @State var templateName = ""
    @State var selectedMood: TodoMood?
    @State var reflectionNotes: String
    @State var hasLocationReminder: Bool
    @State var locationName: String
    @State var locationLatitude: Double?
    @State var locationLongitude: Double?
    @State var notifyOnEntry: Bool
    @State var notifyOnExit: Bool
    @State var isShowingFileImporter = false
    @State var previewingAttachmentURL: URL?
    @State var isShowingMapPicker = false
    @FocusState var isTitleFocused: Bool

    init(todo: CDTodoItem, onDone: (() -> Void)? = nil) {
        self.todo = todo
        self.onDone = onDone
        _title = State(initialValue: todo.title)
        _notes = State(initialValue: todo.notes)
        _selectedStudentIDs = State(initialValue: Set(todo.studentIDsArray))
        _hasDueDate = State(initialValue: todo.dueDate != nil)
        _dueDate = State(initialValue: todo.dueDate ?? AppCalendar.startOfDay(Date()))
        _scheduledDate = State(initialValue: todo.scheduledDate)
        _deadlineDate = State(initialValue: todo.dueDate)
        _isSomeday = State(initialValue: todo.isSomeday)
        _repeatAfterCompletion = State(initialValue: todo.repeatAfterCompletion)
        _customIntervalDays = State(initialValue: todo.customIntervalDays > 0 ? Int(todo.customIntervalDays) : 7)
        _priority = State(initialValue: todo.priority)
        _recurrence = State(initialValue: todo.recurrence)

        // Parse time estimates
        let estTotal = Int(todo.estimatedMinutes)
        _estimatedHours = State(initialValue: estTotal / 60)
        _estimatedMinutes = State(initialValue: estTotal % 60)

        let actTotal = Int(todo.actualMinutes)
        _actualHours = State(initialValue: actTotal / 60)
        _actualMinutes = State(initialValue: actTotal % 60)

        // Parse reminder
        _hasReminder = State(initialValue: todo.reminderDate != nil)
        // Default to 1 hour from now
        _reminderDate = State(initialValue: todo.reminderDate ?? Date().addingTimeInterval(3600))

        // Parse mood and reflection
        _selectedMood = State(initialValue: todo.mood)
        _reflectionNotes = State(initialValue: todo.reflectionNotes)

        // Parse location reminder
        _hasLocationReminder = State(initialValue: todo.hasLocationReminder)
        _locationName = State(initialValue: todo.locationName ?? "")
        _locationLatitude = State(initialValue: todo.locationLatitude != 0 ? todo.locationLatitude : nil)
        _locationLongitude = State(initialValue: todo.locationLongitude != 0 ? todo.locationLongitude : nil)
        _notifyOnEntry = State(initialValue: todo.notifyOnEntry)
        _notifyOnExit = State(initialValue: todo.notifyOnExit)
    }

    var selectedStudents: [CDStudent] {
        students.filter { student in
            guard let id = student.id else { return false }
            return selectedStudentIDs.contains(id.uuidString)
        }
    }

    var canSave: Bool {
        !title.trimmed().isEmpty
    }

    var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
            #else
            iOSLayout
            #endif
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $previewingAttachmentURL) { url in
            AttachmentPreviewSheet(url: url)
        }
    }
}

// MARK: - Subtask Row
struct SubtaskRow: View {
    let subtask: CDTodoSubtask
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onUpdate: (String) -> Void

    @State private var editingTitle: String
    @FocusState private var isFocused: Bool

    init(
        subtask: CDTodoSubtask,
        onToggle: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onUpdate: @escaping (String) -> Void
    ) {
        self.subtask = subtask
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onToggle()
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            TextField("Subtask", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                .strikethrough(subtask.isCompleted)
                .focused($isFocused)
                .onSubmit {
                    saveTitle()
                }
                .onChange(of: isFocused) { _, newValue in
                    if !newValue {
                        saveTitle()
                    }
                }

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.red.opacity(UIConstants.OpacityConstants.prominent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))
        .cornerRadius(8)
        .task {
            if subtask.title.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
    }

    private func saveTitle() {
        let trimmed = editingTitle.trimmed()
        if !trimmed.isEmpty && trimmed != subtask.title {
            onUpdate(trimmed)
        } else if trimmed.isEmpty {
            onDelete()
        }
    }
}

// MARK: - Todo CDStudent Chip
struct TodoStudentChip: View {
    let student: CDStudent
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(student.firstName)
                .font(AppTheme.ScaledFont.bodySemibold)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}
// MARK: - URL Identifiable Conformance

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Attachment Preview Sheet

private struct AttachmentPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .navigationTitle(url.lastPathComponent)
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#if os(iOS)
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
#else
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}
#endif
