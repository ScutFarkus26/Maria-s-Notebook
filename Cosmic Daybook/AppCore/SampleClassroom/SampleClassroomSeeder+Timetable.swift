// SampleClassroomSeeder+Timetable.swift
// The Sample Class's Schedules: our class, the adolescent room, the guide's
// lane and a made-up co-teacher, Morah Rivka, with a week of blocks (Friday
// shorter), turns in the adolescent room, one change on the day it is set up
// (an assembly), and a lesson for the adolescent planned that morning, so
// the page shows a turn with a lesson in it and a gentle warning.

import CoreData
import Foundation

extension SampleClassroomSeeder {

    /// The sample children the timetable names (`fakeStudents`).
    private enum SampleChild {
        static let ari = "A0000000-0000-0000-0000-000000000001"
        static let maya = "A0000000-0000-0000-0000-000000000002"
        static let ezra = "A0000000-0000-0000-0000-000000000005"
        static let tamar = "A0000000-0000-0000-0000-000000000006"
        static let rina = "A0000000-0000-0000-0000-000000000009"
    }

    /// A block's values: `start` in minutes after midnight.
    private static func block(
        _ start: Int, _ length: Int, _ title: String, teacher: UUID? = nil, teacherName: String = "",
        children: [String] = []
    ) -> TimetableBlockValues {
        TimetableBlockValues(
            startMinute: start, lengthMinutes: length, title: title, teacherLaneID: teacher,
            teacherName: teacherName, studentIDs: children
        )
    }

    private static let mondayToThursday: [Weekday] = [.monday, .tuesday, .wednesday, .thursday]

    /// Seeds the lanes, their weekly blocks and the day's change, once: a
    /// store that has any lane is left as it is.
    static func seedTimetableIfNeeded(
        lessons: [LessonSnapshot],
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard try context.count(for: CDFetchRequest(CDTimetableLane.self)) == 0 else { return }

        let lanes = TimetableService.makeStarterLanes(in: context, now: now)
        guard lanes.count == 3, let guideID = lanes[2].id else { return }
        let ourClass = lanes[0]
        let adolescentRoom = lanes[1]
        let rivka = TimetableService.addPerson(named: "Morah Rivka", in: context, now: now)
        let rivkaID = rivka.id

        func add(_ lane: CDTimetableLane, _ days: [Weekday], _ values: TimetableBlockValues) {
            TimetableService.addBlock(values, to: lane, on: days, in: context, now: now, calendar: calendar)
        }

        // Our class: a long day Monday to Thursday, a shorter Friday.
        add(ourClass, mondayToThursday, block(8 * 60 + 30, 15, "Morning meeting"))
        add(ourClass, mondayToThursday, block(8 * 60 + 45, 135, "Work cycle"))
        add(ourClass, mondayToThursday, block(11 * 60, 30, "Recess"))
        add(ourClass, mondayToThursday, block(11 * 60 + 30, 30, "Lunch"))
        add(ourClass, mondayToThursday, block(12 * 60, 90, "Kodesh", teacher: rivkaID))
        add(ourClass, mondayToThursday, block(13 * 60 + 30, 75, "Work cycle"))
        add(ourClass, mondayToThursday, block(14 * 60 + 45, 15, "Closing circle"))
        add(ourClass, [.friday], block(8 * 60 + 30, 15, "Morning meeting"))
        add(ourClass, [.friday], block(8 * 60 + 45, 105, "Work cycle"))
        add(ourClass, [.friday], block(10 * 60 + 30, 45, "Shabbat party"))
        add(ourClass, [.friday], block(11 * 60 + 15, 30, "Lunch"))
        add(ourClass, [.friday], block(11 * 60 + 45, 60, "Kodesh", teacher: rivkaID))

        // The adolescent room: the teachers take turns.
        add(adolescentRoom, Weekday.schoolDays, block(9 * 60, 60, "Math", teacher: guideID))
        add(adolescentRoom, Weekday.schoolDays, block(10 * 60, 60, "Humanities", teacherName: "Mr. Adler"))
        add(adolescentRoom, mondayToThursday, block(13 * 60, 60, "Science", teacherName: "Ms. Park"))
        add(adolescentRoom, mondayToThursday, block(14 * 60, 45, "Torah study", teacher: rivkaID))

        // Morah Rivka's own groups.
        let chumash = [SampleChild.ezra, SampleChild.tamar]
        let reading = [SampleChild.ari, SampleChild.maya]
        add(rivka, Weekday.schoolDays, block(9 * 60 + 15, 45, "Chumash group", children: chumash))
        add(rivka, mondayToThursday, block(10 * 60 + 30, 30, "Hebrew reading", children: reading))

        // The change and the lesson go on the first school day from the day the
        // sample is set up, so a sample made on a weekend shows them (and plans
        // nothing on a day off, bug hunt 2026-10-17 #38).
        let firstSchoolDay = schoolDays(1, from: now, step: 1, in: context, calendar: calendar).first ?? now

        // The change: an assembly that day.
        TimetableService.addOneOff(
            TimetableBlockValues(startMinute: 10 * 60 + 15, lengthMinutes: 30, title: "Assembly", note: "In the gym"),
            to: ourClass, on: firstSchoolDay, in: context, now: now, calendar: calendar
        )

        // A lesson for the adolescent that morning, which lands in the guide's Math turn.
        if let lesson = lessons.last {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson.id.uuidString
            assignment.studentIDs = [SampleChild.rina]
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSectionSnapshot = lesson.section
            assignment.schedule(onDay: firstSchoolDay, using: calendar)
            assignment.notes = "Sample plan—safe to reschedule or complete."
        }
    }
}
