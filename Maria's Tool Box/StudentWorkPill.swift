import SwiftUI
import SwiftData

struct StudentWorkPill: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    let item: ScheduledItem
    let nameForStudentID: (UUID) -> String
    let absentTodayIDs: Set<UUID>

    private var workTypeColor: Color {
        switch item.work.kind {
        case .practiceLesson: return .purple
        case .followUpAssignment: return .orange
        default: return .teal
        }
    }

    private var lessonTitle: String {
        if let lid = UUID(uuidString: item.work.lessonID) {
            let fetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lid })
            if let lesson = try? modelContext.fetch(fetch).first {
                let name = lesson.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return "Work"
    }

    private var studentChips: [(UUID, String, Bool)] {
        let isToday = calendar.isDate(item.checkIn.scheduledDate, inSameDayAs: Date())
        guard let sid = UUID(uuidString: item.work.studentID) else { return [] }
        let name = nameForStudentID(sid).trimmingCharacters(in: .whitespacesAndNewlines)
        let absent = isToday && absentTodayIDs.contains(sid)
        return name.isEmpty ? [] : [(sid, name, absent)]
    }

    struct ChipView: View {
        let label: String
        let isAbsent: Bool
        let tint: Color

        var body: some View {
            Text(label)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(isAbsent ? .secondary : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(isAbsent ? 0.06 : 0.15)))
                .overlay(Capsule().stroke(isAbsent ? Color.red : Color.clear, lineWidth: 1))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(workTypeColor)
                .frame(width: UIConstants.ageIndicatorWidth)
                .opacity(1.0)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(workTypeColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lessonTitle)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if !studentChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(studentChips, id: \.0) { chip in
                                    ChipView(label: chip.1, isAbsent: chip.2, tint: workTypeColor)
                                }
                            }
                        }
                    }

                    let purpose = (item.checkIn.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

#Preview {
    Text("Preview not available without project models")
}
