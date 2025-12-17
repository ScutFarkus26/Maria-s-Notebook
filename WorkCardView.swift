import SwiftUI
import SwiftData

struct WorkCardView: View {
    let contract: WorkContract
    let lessonTitle: String
    let studentDisplay: String
    let needsAttention: Bool
    let metadata: String
    let onOpen: (WorkContract) -> Void
    let onMarkCompleted: (WorkContract) -> Void
    let onScheduleToday: (WorkContract) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(lessonTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer()
                    if needsAttention {
                        Text("Needs Attention")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                            .accessibilityLabel("Needs Attention")
                    }
                }
                Text(studentDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(contract) }
        .contextMenu {
            Button("Open", systemImage: "arrow.forward.circle") { onOpen(contract) }
            Button("Mark Completed", systemImage: "checkmark.circle") { onMarkCompleted(contract) }
            Menu("Schedule", systemImage: "calendar") {
                Button("Today") { onScheduleToday(contract) }
            }
        }
        .draggable(WorkAgendaDragPayload.work(contract.id).stringRepresentation) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lessonTitle).font(.subheadline)
                Text(studentDisplay).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
    }
}

#Preview {
    WorkCardView(
        contract: WorkContract(studentID: UUID().uuidString, lessonID: UUID().uuidString, presentationID: nil, status: .active),
        lessonTitle: "Long Division",
        studentDisplay: "Ada Lovelace",
        needsAttention: true,
        metadata: "7d • Practice",
        onOpen: { _ in },
        onMarkCompleted: { _ in },
        onScheduleToday: { _ in }
    )
    .padding()
}
