// TodayScheduleRows.swift
// Today's Schedule section, read from the Schedules timetable (Plan -
// Schedules, decision 14): the day's blocks from every lane, in time order,
// except the guide's own lessons, which Today already lists. A turn shows
// once, as "Your turn in the adolescent room"; a block changed for the day
// is marked, and a person out is a row of her own.

import CoreData
import Foundation

enum TodayScheduleRows {

    /// What a row says about the day.
    enum Mark: Equatable {
        /// A one-off on the day.
        case todayOnly
        /// A weekly block with the day's own values.
        case changed
        /// A person out on the day.
        case out
    }

    /// One line of the section.
    struct Row: Identifiable, Equatable {
        let id: String
        /// "10:30–11:45"; nil for a person out.
        let time: String?
        let title: String
        /// Who teaches it, whose lane it is, or the children.
        let detail: String?
        let lane: TimetableLaneSnapshot
        let mark: Mark?
        let startMinute: Int
    }

    /// The day worked out by the resolver, without the guide's lessons (Today
    /// lists them already). Empty on a day with no school.
    static func day(
        _ day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> ScheduleDay {
        let timetable = TimetableService.timetable(from: day, through: day, in: context, calendar: calendar)
        return ScheduleDayResolver.resolve(ScheduleDayResolver.Input(
            day: day, lanes: timetable.lanes, blocks: timetable.blocks, changes: timetable.changes,
            isSchoolDay: timetable.lanes.isEmpty || SchoolDayChecker.isSchoolDay(day, using: context),
            calendar: calendar
        ))
    }

    /// The section's rows for a resolved day. `names` gives a child's short name.
    static func rows(_ day: ScheduleDay, names: (String) -> String? = { _ in nil }) -> [Row] {
        guard day.isSchoolDay else { return [] }
        let lanes = Dictionary(day.lanes.map { ($0.id, $0.lane) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(day.lanes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [Row] = []
        for lane in day.lanes {
            if lane.isOut {
                rows.append(Row(
                    id: "out-\(lane.id.uuidString)", time: nil,
                    title: ScheduleText.outLine(lane.lane.name, isToday: true), detail: nil,
                    lane: lane.lane, mark: .out, startMinute: -1
                ))
            }
            for item in lane.items {
                // A turn is the room's block, listed once from the room; lessons are Today's own.
                guard case .block(let block) = item.kind else { continue }
                rows.append(row(block, lane: lane.lane, lanes: lanes, names: names))
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
            let left = order[lhs.lane.id] ?? 0
            let right = order[rhs.lane.id] ?? 0
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    /// The section's rows, children named from Today's student cache.
    static func rows(_ day: ScheduleDay, students: [UUID: CDStudent]) -> [Row] {
        rows(day) { id in UUID(uuidString: id).flatMap { students[$0]?.shortName } }
    }

    private static func row(
        _ block: ScheduleDay.Block,
        lane: TimetableLaneSnapshot,
        lanes: [UUID: TimetableLaneSnapshot],
        names: (String) -> String?
    ) -> Row {
        let values = block.values
        let title = values.title.trimmed()
        var heading = title.isEmpty ? lane.name : title
        var detail: String?
        if let teacherID = block.teacherLaneID, lanes[teacherID]?.isGuide == true, lane.kind == .room {
            heading = block.teacherIsOut
                ? ScheduleText.turnTitle(room: lane.name, title: title)
                : ScheduleText.yourTurnTitle(room: lane.name, title: title)
            detail = block.teacherIsOut ? "You're out" : nil
        } else if lane.kind == .room {
            let teacher = ScheduleText.teacher(of: values, lanes: lanes)
            detail = [lane.name, teacher.map { block.teacherIsOut ? "\($0) is out" : $0 }]
                .compactMap { $0 }.joined(separator: " · ")
        } else {
            detail = [lane.name, ScheduleText.children(values.studentIDs, name: names)]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let mark: Mark? = block.isOneOff ? .todayOnly : (block.isChanged ? .changed : nil)
        return Row(
            id: "block-\(block.id.uuidString)", time: TimetableDay.rangeText(values), title: heading,
            detail: detail, lane: lane, mark: mark, startMinute: values.startMinute
        )
    }
}
