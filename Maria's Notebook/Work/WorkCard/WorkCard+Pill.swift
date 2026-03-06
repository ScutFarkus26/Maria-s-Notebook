import SwiftUI
import SwiftData

/// Pill mode content for WorkCard
/// Displays: color bar, lesson title, student chips with absence indicators, check-in note
/// Used in Today view for scheduled work items
struct WorkCardPillContent: View {
    let config: WorkCard.PillModeConfig

    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    private var workKind: WorkCardWorkKind {
        WorkCardWorkKind(from: config.item.work.kind)
    }

    private var lessonTitle: String {
        if let lid = UUID(uuidString: config.item.work.lessonID) {
            let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lid })
            if let lesson = modelContext.safeFetchFirst(fetch) {
                let name = lesson.name.trimmed()
                if !name.isEmpty { return name }
            }
        }
        return "Work"
    }

    private struct StudentChipData: Identifiable {
        let id: UUID
        let name: String
        let isAbsent: Bool
    }

    private var studentChips: [StudentChipData] {
        let isToday = calendar.isDate(config.item.checkIn.date, inSameDayAs: Date())
        guard let sid = UUID(uuidString: config.item.work.studentID) else { return [] }
        let name = config.nameForStudentID(sid).trimmed()
        let absent = isToday && config.absentTodayIDs.contains(sid)
        return name.isEmpty ? [] : [StudentChipData(id: sid, name: name, isAbsent: absent)]
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(workKind.color)
                .frame(width: UIConstants.ageIndicatorWidth)
                .opacity(1.0)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(workKind.color)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lessonTitle)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if !studentChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(studentChips) { chip in
                                    StudentChipView(label: chip.name, isAbsent: chip.isAbsent, tint: workKind.color)
                                }
                            }
                        }
                    }

                    let purpose = config.item.checkIn.latestUnifiedNoteText.trimmed()
                    if !purpose.isEmpty {
                        Text(purpose)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

/// Student chip for pill mode
private struct StudentChipView: View {
    let label: String
    let isAbsent: Bool
    let tint: Color

    var body: some View {
        Text(label)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(isAbsent ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(isAbsent ? 0.06 : 0.15)))
            .overlay(Capsule().stroke(isAbsent ? Color.red : Color.clear, lineWidth: 1))
    }
}

#Preview {
    Text("Preview requires ScheduledItem model")
}
