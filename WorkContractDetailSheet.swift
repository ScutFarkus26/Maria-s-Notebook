import SwiftUI
import SwiftData

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Environment(\.calendar) private var calendar
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]

    private var lessonsByID: [UUID: Lesson] { Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) }) }
    private var studentsByID: [UUID: Student] { Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) }) }

    @State private var status: WorkStatus
    @State private var hasSchedule: Bool
    @State private var scheduledDate: Date

    init(contract: WorkContract, onDone: (() -> Void)? = nil) {
        self.contract = contract
        self.onDone = onDone
        _status = State(initialValue: contract.status)
        let d = contract.scheduledDate ?? Date()
        _hasSchedule = State(initialValue: contract.scheduledDate != nil)
        _scheduledDate = State(initialValue: d)
    }

    private func lessonTitle() -> String {
        if let lid = UUID(uuidString: contract.lessonID), let l = lessonsByID[lid] {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "Lesson"
    }
    private func studentName() -> String {
        if let sid = UUID(uuidString: contract.studentID), let s = studentsByID[sid] {
            return StudentFormatter.displayName(for: s)
        }
        return "Student"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lessonTitle())
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(studentName())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    status = .complete
                    hasSchedule = false
                    contract.status = .complete
                    contract.completedAt = Date()
                    contract.scheduledDate = nil
                    try? modelContext.save()
                    close()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("Status", selection: $status) {
                ForEach(WorkStatus.allCases, id: \.self) { s in
                    Text(label(for: s)).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Schedule", isOn: $hasSchedule)
            if hasSchedule {
                DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
            }

            HStack {
                Spacer()
                Button("Cancel") { close() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 360)
        .presentationSizing(.fitted)
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private func label(for s: WorkStatus) -> String {
        switch s {
        case .active: return "Active"
        case .review: return "Review"
        case .complete: return "Complete"
        }
    }

    private func close() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func save() {
        contract.status = status
        contract.scheduledDate = hasSchedule ? AppCalendar.startOfDay(scheduledDate) : nil
        if status == .complete {
            contract.completedAt = Date()
        } else {
            contract.completedAt = nil
        }
        try? modelContext.save()
        close()
    }
}

#Preview {
    let schema = AppSchema.schema
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let ctx = container.mainContext

    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(), level: .upper)
    let lesson = Lesson(name: "Long Division", subject: "Math", group: "Operations", subheading: "", writeUp: "")
    ctx.insert(student); ctx.insert(lesson)
    let c = WorkContract(studentID: student.id.uuidString, lessonID: lesson.id.uuidString, status: .active, scheduledDate: Date())
    ctx.insert(c)
    return WorkContractDetailSheet(contract: c)
        .previewEnvironment(using: container)
}

