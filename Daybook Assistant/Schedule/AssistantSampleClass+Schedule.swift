import Foundation
import CoreData

// The sample class's schedule: the two rooms, the guide and a co-teacher,
// a week of blocks, one change today, and two of the guide's lessons booked
// for today, as the notebook would publish them (children only).

extension AssistantSampleClass {

    /// The sample co-teacher, a made-up name like the rest of the class.
    static let coTeacherName = "Morah Tova"

    /// Lanes, a Monday-to-Friday timetable (Friday shorter), a change to the
    /// adolescent room's math today, and two bookings today: one morning
    /// lesson for two upper-elementary children, and one at 9:30 for two
    /// adolescents, which lands in the guide's turn in the adolescent room.
    static func seedSchedule(in context: NSManagedObjectContext, now: Date = Date()) {
        let calendar = AppCalendar.shared
        let today = calendar.startOfDay(for: now)

        let ourClass = lane("Our class", kind: .room, sortOrder: 0, color: "blue", in: context)
        let adolescent = lane("Adolescent room", kind: .room, sortOrder: 1, color: "purple", in: context)
        let guide = lane(guideName, kind: .person, sortOrder: 2, color: "green", in: context)
        guide.isGuide = true
        let coTeacher = lane(coTeacherName, kind: .person, sortOrder: 3, color: "orange", in: context)

        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
            .sorted { ($0.firstName, $0.lastName) < ($1.firstName, $1.lastName) }
        func ids(_ firstNames: [String]) -> [String] {
            firstNames.compactMap { first in students.first { $0.firstName == first }?.id?.uuidString }
        }

        var math: CDTimetableBlock?
        for weekday in Weekday.schoolDays {
            let friday = weekday == .friday
            @discardableResult
            func add(_ lane: CDTimetableLane, _ start: Int, _ length: Int, _ title: String,
                     teacher: CDTimetableLane? = nil, teacherName: String = "", children: [String] = [])
                -> CDTimetableBlock {
                block(in: lane, weekday: weekday, values: TimetableBlockValues(
                    startMinute: start, lengthMinutes: length, title: title,
                    teacherLaneID: teacher?.id, teacherName: teacherName, studentIDs: children
                ), context: context, now: now)
            }
            add(ourClass, 8 * 60 + 30, 15, "Morning meeting")
            add(ourClass, 8 * 60 + 45, 180, "Work period")
            add(ourClass, 11 * 60 + 45, 60, "Lunch and recess")
            let afternoon = friday ? "Clean-up and Shabbat party" : "Afternoon work period"
            add(ourClass, 12 * 60 + 45, friday ? 75 : 135, afternoon)
            add(adolescent, 9 * 60, 90, "Humanities", teacher: guide)
            let mathBlock = add(adolescent, 10 * 60 + 30, 75, "Math", teacherName: "Mr. Okafor")
            if TimetableDay.weekday(of: today, calendar: calendar) == weekday { math = mathBlock }
            if !friday {
                add(adolescent, 13 * 60 + 15, 75, "Science", teacher: coTeacher)
                add(coTeacher, 9 * 60, 45, "Chumash group", children: ids(["Ari", "Leah", "Ezra"]))
            }
        }

        // Today the math block runs late, for the "1 change today" line.
        if let math, let mathID = math.id {
            var values = math.values
            values.startMinute = 10 * 60 + 45
            values.lengthMinutes = 60
            let change = CDTimetableChange(context: context)
            change.day = today
            change.kind = .changed
            change.blockID = mathID.uuidString
            change.values = values
            change.modifiedAt = now
        }

        // Two of the guide's lessons, as bookings: never a lesson's name.
        booking(on: today, at: nil, order: 0, children: ids(["Maya", "Eli"]), in: context)
        booking(on: today, at: 9 * 60 + 30, order: 1, children: ids(["Noah", "Tamar"]), in: context)
    }

    private static func lane(
        _ name: String, kind: TimetableLaneKind, sortOrder: Int, color: String, in context: NSManagedObjectContext
    ) -> CDTimetableLane {
        let lane = CDTimetableLane(context: context)
        lane.name = name
        lane.kind = kind
        lane.sortOrder = Int64(sortOrder)
        lane.colorRaw = color
        return lane
    }

    @discardableResult
    private static func block(
        in lane: CDTimetableLane, weekday: Weekday, values: TimetableBlockValues,
        context: NSManagedObjectContext, now: Date
    ) -> CDTimetableBlock {
        let block = CDTimetableBlock(context: context)
        block.laneID = lane.id?.uuidString ?? ""
        block.weekday = weekday
        block.apply(values)
        block.createdAt = now
        block.modifiedAt = now
        return block
    }

    /// A morning lesson, at `minute` if it has a set time.
    private static func booking(
        on day: Date, at minute: Int?, order: Int, children: [String], in context: NSManagedObjectContext
    ) {
        let booking = CDTimetableBooking(context: context)
        booking.presentationID = UUID().uuidString
        booking.day = day
        booking.half = minute.map(ScheduleDayHalf.init(minute:)) ?? .morning
        booking.setMinute = minute
        booking.order = Int64(order)
        booking.studentIDs = children
        booking.sourceModifiedAt = booking.createdAt
    }
}
