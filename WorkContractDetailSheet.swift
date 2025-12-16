import SwiftUI
import SwiftData

struct WorkContractDetailSheet: View {
    let contract: WorkContract
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Work Details").font(.title3).bold()

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
    let schema = Schema([WorkContract.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let c = WorkContract(studentID: UUID().uuidString, lessonID: UUID().uuidString)
    container.mainContext.insert(c)
    return WorkContractDetailSheet(contract: c)
        .previewEnvironment(using: container)
}

