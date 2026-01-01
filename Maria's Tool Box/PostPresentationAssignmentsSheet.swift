import SwiftUI
import SwiftData

struct PostPresentationAssignmentsSheet: View {
    struct AssignmentEntry: Identifiable {
        let id = UUID()
        var studentID: UUID
        var text: String
        var schedule: Schedule?
    }
    enum ScheduleKind: String, CaseIterable, Identifiable {
        case checkIn
        case dueDate
        var id: String { rawValue }
        var label: String { self == .checkIn ? "Check-in" : "Due Date" }
    }
    struct Schedule {
        var date: Date
        var kind: ScheduleKind
    }

    let students: [Student]
    let lessonName: String
    var onCreate: ([AssignmentEntry]) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var defaultScheduleEnabled: Bool = false
    @State private var defaultScheduleDate: Date = AppCalendar.startOfDay(Date().addingTimeInterval(24*60*60))
    @State private var defaultScheduleKind: ScheduleKind = .checkIn

    @State private var entries: [UUID: AssignmentEntry] = [:]
    @State private var bulkText: String = ""

    init(students: [Student], lessonName: String, onCreate: @escaping ([AssignmentEntry]) -> Void, onCancel: @escaping () -> Void) {
        self.students = students
        self.lessonName = lessonName
        self.onCreate = onCreate
        self.onCancel = onCancel
        _entries = State(initialValue: Dictionary(uniqueKeysWithValues: students.map { ($0.id, AssignmentEntry(studentID: $0.id, text: "", schedule: nil)) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assignments for \(lessonName)")
                    .font(.headline)
                Spacer()
            }

            // Bulk helpers
            VStack(alignment: .leading, spacing: 8) {
                TextField("Set same assignment for all…", text: $bulkText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Apply to All") { applyBulkText() }
                    Spacer()
                    Toggle("Default Schedule", isOn: $defaultScheduleEnabled)
                    if defaultScheduleEnabled {
                        DatePicker("Date", selection: $defaultScheduleDate, displayedComponents: .date)
                        Picker("Kind", selection: $defaultScheduleKind) {
                            ForEach(ScheduleKind.allCases) { k in Text(k.label).tag(k) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            // Per-student entries
            List {
                ForEach(students, id: \.id) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(StudentFormatter.displayName(for: s))
                            .font(.subheadline.weight(.semibold))
                        TextField("Assignment for \(StudentFormatter.displayName(for: s))…", text: Binding(
                            get: { entries[s.id]?.text ?? "" },
                            set: { entries[s.id]?.text = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        // Per-student schedule
                        let isOn = Binding<Bool>(
                            get: { entries[s.id]?.schedule != nil },
                            set: { newValue in
                                if newValue {
                                    var e = entries[s.id] ?? AssignmentEntry(studentID: s.id, text: "", schedule: nil)
                                    if e.schedule == nil {
                                        e.schedule = Schedule(date: defaultScheduleDate, kind: defaultScheduleKind)
                                    }
                                    entries[s.id] = e
                                } else {
                                    var e = entries[s.id]
                                    e?.schedule = nil
                                    if let e { entries[s.id] = e }
                                }
                            }
                        )
                        Toggle("Schedule", isOn: isOn)
                        if let sch = entries[s.id]?.schedule {
                            DatePicker("Date", selection: Binding(
                                get: { sch.date },
                                set: { newDate in
                                    var e = entries[s.id]!
                                    e.schedule?.date = newDate
                                    entries[s.id] = e
                                }
                            ), displayedComponents: .date)
                            Picker("Kind", selection: Binding(
                                get: { sch.kind },
                                set: { newKind in
                                    var e = entries[s.id]!
                                    e.schedule?.kind = newKind
                                    entries[s.id] = e
                                }
                            )) {
                                ForEach(ScheduleKind.allCases) { k in Text(k.label).tag(k) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel(); dismiss() }
                Button("Create") {
                    var result: [AssignmentEntry] = []
                    for s in students {
                        if var e = entries[s.id] {
                            // Apply default schedule if enabled and no per-student schedule set
                            if defaultScheduleEnabled && e.schedule == nil {
                                e.schedule = Schedule(date: defaultScheduleDate, kind: defaultScheduleKind)
                            }
                            result.append(e)
                        }
                    }
                    onCreate(result)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        .presentationSizingFitted()
    #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private func applyBulkText() {
        let trimmed = bulkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for s in students { entries[s.id]?.text = trimmed }
    }
}
