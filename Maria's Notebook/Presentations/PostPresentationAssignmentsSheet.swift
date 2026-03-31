import SwiftUI
import CoreData

struct PostPresentationAssignmentsSheet: View {
    struct AssignmentEntry: Identifiable {
        let id = UUID()
        var studentID: UUID
        var text: String
        var schedule: Schedule?
    }
    enum ScheduleKind: String, CaseIterable, Identifiable, Sendable {
        case checkIn
        case dueDate
        var id: String { rawValue }
        var label: String { self == .checkIn ? "Check-in" : "Due Date" }
    }
    struct Schedule {
        var date: Date
        var kind: ScheduleKind
    }

    let students: [CDStudent]
    let lessonName: String
    var onCreate: ([AssignmentEntry]) -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var defaultScheduleEnabled: Bool = false
    @State private var defaultScheduleDate: Date = AppCalendar.startOfDay(Date().addingTimeInterval(24*60*60))
    @State private var defaultScheduleKind: ScheduleKind = .checkIn

    @State private var entries: [UUID: AssignmentEntry] = [:]
    @State private var bulkText: String = ""

    init(
        students: [CDStudent], lessonName: String,
        onCreate: @escaping ([AssignmentEntry]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // DEDUPLICATION: Defensive deduplication in case caller doesn't deduplicate
        let deduped = students.uniqueByID
        self.students = deduped
        self.lessonName = lessonName
        self.onCreate = onCreate
        self.onCancel = onCancel
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        _entries = State(initialValue: Dictionary(
            deduped.compactMap { guard let id = $0.id else { return nil }; return (id, AssignmentEntry(studentID: id, text: "", schedule: nil)) },
            uniquingKeysWith: { first, _ in first }
        ))
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
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(UIConstants.OpacityConstants.trace)))

            // Per-student entries
            List {
                ForEach(students, id: \.objectID) { s in
                    if let sID = s.id {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(StudentFormatter.displayName(for: s))
                                .font(.subheadline.weight(.bold))
                            TextField("Assignment for \(StudentFormatter.displayName(for: s))…", text: Binding(
                                get: { entries[sID]?.text ?? "" },
                                set: { entries[sID]?.text = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            // Per-student schedule
                            let isOn = Binding<Bool>(
                                get: { entries[sID]?.schedule != nil },
                                set: { newValue in
                                    if newValue {
                                        var e = entries[sID] ?? AssignmentEntry(studentID: sID, text: "", schedule: nil)
                                        if e.schedule == nil {
                                            e.schedule = Schedule(date: defaultScheduleDate, kind: defaultScheduleKind)
                                        }
                                        entries[sID] = e
                                    } else {
                                        var e = entries[sID]
                                        e?.schedule = nil
                                        if let e { entries[sID] = e }
                                    }
                                }
                            )
                            Toggle("Schedule", isOn: isOn)
                            if let sch = entries[sID]?.schedule {
                                DatePicker("Date", selection: Binding(
                                    get: { sch.date },
                                    set: { newDate in
                                        guard var e = entries[sID] else { return }
                                        e.schedule?.date = newDate
                                        entries[sID] = e
                                    }
                                ), displayedComponents: .date)
                                Picker("Kind", selection: Binding(
                                    get: { sch.kind },
                                    set: { newKind in
                                        guard var e = entries[sID] else { return }
                                        e.schedule?.kind = newKind
                                        entries[sID] = e
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
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel(); dismiss() }
                Button("Create") {
                    var result: [AssignmentEntry] = []
                    for s in students {
                        guard let sID = s.id else { continue }
                        if var e = entries[sID] {
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
        let trimmed = bulkText.trimmed()
        guard !trimmed.isEmpty else { return }
        for s in students { guard let sID = s.id else { continue }; entries[sID]?.text = trimmed }
    }
}
