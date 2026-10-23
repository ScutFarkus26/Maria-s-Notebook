import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

/// What the Schedule tab's tests share: a store, a Monday (2026-10-26) and
/// 9:15 that morning, and the guide's records as the notebook writes them.
@MainActor
protocol AssistantScheduleFixture {
    var stack: CoreDataStack { get }
    /// A Monday.
    var monday: Date { get }
    /// 9:15 that Monday.
    var morning: Date { get }
}

/// Our class, the adolescent room, the guide and a co-teacher.
struct AssistantScheduleLanes {
    let ourClass: CDTimetableLane
    let adolescent: CDTimetableLane
    let guide: CDTimetableLane
    let coTeacher: CDTimetableLane
}

@MainActor
extension AssistantScheduleFixture {

    var context: NSManagedObjectContext { stack.viewContext }

    func makeLanes() -> AssistantScheduleLanes {
        func lane(_ name: String, _ kind: TimetableLaneKind, guide: Bool = false, order: Int) -> CDTimetableLane {
            let lane = CDTimetableLane(context: context)
            lane.name = name
            lane.kind = kind
            lane.isGuide = guide
            lane.sortOrder = Int64(order)
            return lane
        }
        return AssistantScheduleLanes(
            ourClass: lane("Our class", .room, order: 0),
            adolescent: lane("Adolescent room", .room, order: 1),
            guide: lane("Danny", .person, guide: true, order: 2),
            coTeacher: lane("Morah Devora", .person, order: 3)
        )
    }

    @discardableResult
    func block(
        _ lane: CDTimetableLane, _ start: Int, _ length: Int, _ title: String,
        teacher: CDTimetableLane? = nil, children: [String] = [], weekday: Weekday = .monday
    ) -> CDTimetableBlock {
        let block = CDTimetableBlock(context: context)
        block.laneID = lane.id?.uuidString ?? ""
        block.weekday = weekday
        block.apply(TimetableBlockValues(
            startMinute: start, lengthMinutes: length, title: title, teacherLaneID: teacher?.id,
            studentIDs: children
        ))
        return block
    }

    @discardableResult
    func booking(
        _ children: [CDStudent], half: ScheduleDayHalf = .morning, minute: Int? = nil, order: Int = 0,
        presentationID: UUID = UUID(), sourceModifiedAt: Date? = nil
    ) -> CDTimetableBooking {
        let booking = CDTimetableBooking(context: context)
        booking.presentationID = presentationID.uuidString
        booking.day = monday
        booking.half = half
        booking.setMinute = minute
        booking.order = Int64(order)
        booking.studentIDs = children.compactMap { $0.id?.uuidString }
        booking.sourceModifiedAt = sourceModifiedAt ?? monday
        return booking
    }

    func student(_ first: String, _ last: String, _ level: CDStudent.Level) -> CDStudent {
        let student = AssistantTestSupport.student(first, last, in: context)
        student.level = level
        return student
    }

    func model(guideName: String? = "Danny") -> AssistantScheduleModel {
        let now = morning
        let model = AssistantScheduleModel(context: context, guideName: { guideName }, now: { now })
        model.load()
        return model
    }
}
