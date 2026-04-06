import SwiftUI

struct YearPlanDayCell: View {
    let cellID: CellID
    let isToday: Bool
    let isNonSchool: Bool
    let items: [YearPlanCalendarItem]
    let lessonsByID: [String: CDLesson]
    let onDrop: ((UUID, CellID) -> Void)?

    @Binding var popoverCellID: CellID?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 4) {
            dayNumber

            if items.isEmpty {
                holidayLabel
            } else {
                itemPills
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .background(isDropTargeted ? Color.accentColor.opacity(UIConstants.OpacityConstants.accent) : Color.clear)
        .onTapGesture {
            if !items.isEmpty {
                popoverCellID = cellID
            }
        }
        .dropDestination(for: String.self) { strings, _ in
            guard let str = strings.first,
                  let payload = UnifiedCalendarDragPayload.parse(str),
                  case .yearPlanEntry(let entryID) = payload else { return false }
            onDrop?(entryID, cellID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    // MARK: - Day Number

    private var dayNumber: some View {
        Text("\(cellID.day)")
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(dayNumberColor)
            .frame(width: 22, height: 22)
            .background {
                if isToday {
                    Circle().fill(Color.accentColor)
                }
            }
    }

    private var dayNumberColor: Color {
        if isToday { return .white }
        if isNonSchool { return .red.opacity(UIConstants.OpacityConstants.half) }
        return .secondary
    }

    // MARK: - Holiday

    @ViewBuilder
    private var holidayLabel: some View {
        if let holiday = PerpetualHolidays.holiday(month: cellID.month, day: cellID.day, year: cellID.year) {
            Text(holiday)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Item Pills

    private var itemPills: some View {
        HStack(spacing: 3) {
            ForEach(items.prefix(3)) { item in
                let pill = YearPlanPill(item: item, lesson: lessonsByID[item.lessonID])
                if item.isEditable {
                    pill.draggable(
                        UnifiedCalendarDragPayload.yearPlanEntry(item.id).stringRepresentation
                    ) {
                        YearPlanPill(item: item, lesson: lessonsByID[item.lessonID])
                            .opacity(UIConstants.OpacityConstants.almostOpaque)
                    }
                } else {
                    pill
                }
            }
            if items.count > 3 {
                Text("+\(items.count - 3)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Year Plan Pill

struct YearPlanPill: View {
    let item: YearPlanCalendarItem
    let lesson: CDLesson?

    private var abbreviatedName: String {
        let name = lesson?.name ?? "?"
        if name.count <= 8 { return name }
        return String(name.prefix(7)) + "."
    }

    private var subjectColor: Color {
        AppColors.color(forSubject: lesson?.subject ?? "")
    }

    private var paceColor: Color {
        switch item.displayStatus {
        case .promoted: return .green
        case .skipped: return .gray
        case .behindPace: return .red
        case .planned: return .gray
        case .scheduled: return .blue
        case .presented: return .green
        }
    }

    private var isMuted: Bool {
        switch item.displayStatus {
        case .promoted, .presented: return true
        default: return false
        }
    }

    private var isStrikethrough: Bool {
        item.displayStatus == .promoted
    }

    private var showBorder: Bool {
        switch item.displayStatus {
        case .behindPace, .scheduled: return true
        default: return false
        }
    }

    var body: some View {
        Text(abbreviatedName)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .strikethrough(isStrikethrough)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(subjectColor.opacity(UIConstants.OpacityConstants.moderate))
            )
            .foregroundStyle(subjectColor)
            .opacity(isMuted ? UIConstants.OpacityConstants.muted : 1)
            .overlay(
                Capsule()
                    .strokeBorder(paceColor, lineWidth: showBorder ? 1.5 : 0)
            )
            .lineLimit(1)
    }
}
