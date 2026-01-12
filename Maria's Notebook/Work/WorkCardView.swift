import SwiftUI
import SwiftData

struct WorkCardView: View {
    let work: WorkModel
    let lessonTitle: String
    let studentDisplay: String
    let needsAttention: Bool
    let metadata: String
    let ageSchoolDays: Int
    let onOpen: (WorkModel) -> Void
    let onMarkCompleted: (WorkModel) -> Void
    let onScheduleToday: (WorkModel) -> Void

    @SyncedAppStorage("WorkAge.warningDays") private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage("WorkAge.overdueDays") private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage("WorkAge.freshColorHex") private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage("WorkAge.warningColorHex") private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage("WorkAge.overdueColorHex") private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    private var ageStatus: LessonAgeStatus {
        if ageSchoolDays >= max(0, ageOverdueDays) { return .overdue }
        if ageSchoolDays >= max(0, ageWarningDays) { return .warning }
        return .fresh
    }
    private var ageColor: Color {
        switch ageStatus {
        case .fresh: return ColorUtils.color(from: ageFreshColorHex)
        case .warning: return ColorUtils.color(from: ageWarningColorHex)
        case .overdue: return ColorUtils.color(from: ageOverdueColorHex)
        }
    }

    private var kindText: String {
        switch work.status {
        case .active: return "Practice"
        case .review: return "Follow-Up"
        case .complete: return "Completed"
        }
    }

    private var displayTitle: String {
        let trimmedTitle = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return lessonTitle
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(ageColor)
                .frame(width: UIConstants.ageIndicatorWidth)
                .opacity(work.status == .complete ? 0.0 : 1.0)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(displayTitle)
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
                    HStack(spacing: 8) {
                        Text(studentDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(kindText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(ageSchoolDays)d")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { onOpen(work) }
        .contextMenu {
            Button("Open", systemImage: "arrow.forward.circle") { onOpen(work) }
            Button("Mark Completed", systemImage: "checkmark.circle") { onMarkCompleted(work) }
            Menu("Schedule", systemImage: "calendar") {
                Button("Today") { onScheduleToday(work) }
            }
        }
        .draggable(WorkAgendaDragPayload.work(work.id).stringRepresentation) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle).font(.subheadline)
                Text(studentDisplay).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
    }
}

#Preview {
    WorkCardView(
        work: WorkModel(status: .active, studentID: UUID().uuidString, lessonID: UUID().uuidString),
        lessonTitle: "Long Division",
        studentDisplay: "Ada Lovelace",
        needsAttention: true,
        metadata: "7d • Practice",
        ageSchoolDays: 7,
        onOpen: { _ in },
        onMarkCompleted: { _ in },
        onScheduleToday: { _ in }
    )
    .padding()
}

