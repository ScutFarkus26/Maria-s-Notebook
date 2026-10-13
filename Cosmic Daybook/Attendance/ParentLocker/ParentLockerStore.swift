import Foundation
import CoreData

/// One day as `ParentLockerSync` needs it, read from the store in one go:
/// how the guide sends attendance, who this device is, whether the day has
/// reached "after" (arrival closed, or a ParentLocker send recorded), and
/// the children with their marks.
nonisolated struct ParentLockerDay: Sendable, Equatable {
    var method: AttendanceSendMethod = .email
    /// The site's host (`AttendanceEmailLog.parentLockerHost`).
    var site: String = AttendanceEmailLog.defaultParentLockerSite
    var role: CDClassroomMembership.ClassroomRole = .leadGuide
    var isSchoolDay = true
    /// A record that day carries Close Arrival's automatic absence
    /// (`CDAttendanceStore.arrivalClosed(on:)`), on this device or synced in.
    var arrivalClosed = false
    /// A send by ParentLocker is recorded for the day.
    var sentToParentLocker = false
    /// ParentLocker said it isn't expecting the class's attendance that day
    /// (`AttendanceEmailLog.isNotExpected`), on this device or another. Not
    /// a send: the day isn't "after" for it.
    var notExpected = false
    /// When the day's attendance is due, in minutes after midnight
    /// (`AttendanceEmailLog.Settings.deadlineMinutes`).
    var deadlineMinutes = AttendanceEmailLog.defaultDeadlineMinutes
    /// The day's roll.
    var children: [ParentLockerPlanner.Child] = []
    /// Each child's mark, from the record that wins among the day's duplicates.
    var marks: [UUID: ParentLockerPlanner.DayMark] = [:]

    /// Live updates start once arrival has closed or the day has been sent
    /// (plan "ParentLocker attendance", What counts as "after").
    var isAfter: Bool { arrivalClosed || sentToParentLocker }

    /// Everyone on the roll who goes to ParentLocker has a mark to send: the
    /// class has been taken, though maybe closed with nobody left to mark
    /// (which writes no automatic absence). The guide's "Not matched"
    /// children never go there, so they aren't waited for, as
    /// `unmarkedChildren` leaves them out. Read with the children only.
    var everyoneMarked: Bool {
        children.contains { !Self.isLeftOut($0) } && unmarkedChildren.isEmpty
    }

    /// Someone on the roll has a mark to send. Reset Day leaves nobody: a
    /// Close Arrival & Send waiting then has nothing to send. Read with the
    /// children only.
    var anyoneMarked: Bool {
        children.contains { ParentLockerPlanner.wanted(for: marks[$0.id]) != .nothing }
    }

    /// The children on the roll with no mark to send yet, but for those the
    /// guide left out of ParentLocker ("Not matched"), who never go there.
    /// Read with the children only.
    var unmarkedChildren: [ParentLockerPlanner.Child] {
        children.filter { ParentLockerPlanner.wanted(for: marks[$0.id]) == .nothing && !Self.isLeftOut($0) }
    }

    /// The guide left the child out of ParentLocker ("Not matched").
    private static func isLeftOut(_ child: ParentLockerPlanner.Child) -> Bool {
        child.parentLockerID.map(ParentLockerPlanner.isNotMatched) ?? false
    }

    /// Their names as the class reads them ("Maya S"), in name order.
    var unmarkedNames: [String] {
        unmarkedChildren.map { CDStudent.shortName(firstName: $0.firstName, lastName: $0.lastName) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// When `day`'s attendance is due.
    func deadline(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .minute, value: deadlineMinutes, to: calendar.startOfDay(for: day))
    }

    /// "Maya S", for the status line's problems; "a child" for one not on the roll.
    func name(of childID: UUID) -> String {
        guard let child = children.first(where: { $0.id == childID }) else { return "a child" }
        return CDStudent.shortName(firstName: child.firstName, lastName: child.lastName)
    }
}

extension AttendanceRow {
    /// Still to be marked before the day goes to ParentLocker: unmarked, and
    /// not one the guide left out of ParentLocker ("Not matched"), who never
    /// goes there. The screens count as the sync does
    /// (`ParentLockerDay.unmarkedChildren`), so they offer Send when the line
    /// says everyone's marked.
    var waitsForParentLocker: Bool {
        status == .unmarked && !(student.parentLockerID.map(ParentLockerPlanner.isNotMatched) ?? false)
    }
}

/// What the sync reads from the notebook and writes back. The apps use
/// `ParentLockerCoreDataStore`; the tests a fake.
@MainActor
protocol ParentLockerStore: AnyObject {
    /// `day` as the sync reads it; without the roll and marks unless
    /// `withChildren`, for the cheap check each save makes.
    func day(_ day: Date, withChildren: Bool) -> ParentLockerDay
    /// The ParentLocker host the guide set, read on its own.
    var site: String { get }
    /// The children whose records on `day` are among `records`.
    func children(inRecords records: [NSManagedObjectID], on day: Date) -> Set<UUID>
    /// The marks of `children` on `day` as they are now, one per child
    /// (`ParentLockerPlanner.dayMarks`); a child with no record has none.
    func marks(of children: Set<UUID>, on day: Date) -> [UUID: ParentLockerPlanner.DayMark]
    /// Records that `day` went to ParentLocker. Returns whether it saved.
    func recordSend(on day: Date) -> Bool
    /// ParentLocker expects no attendance from the class on `day`: noted in
    /// the classroom share once, so every device's reminder for it is
    /// withdrawn (`FrontDeskEmailReminder`) and every device's line says so.
    func noteNotExpected(on day: Date)
    /// Stores ParentLocker ids on the children (nil clears one, and
    /// `ParentLockerPlanner.notMatchedID` is "Not matched"); a picked id is
    /// cleared from any other child who held it. Only the lead guide's
    /// devices write them. Returns whether it saved.
    func writeMatches(_ matches: [UUID: String?]) -> Bool
}

/// The sync's store on a Core Data context: the notebook's view context, or
/// the Assistant's, where it reads only the classroom share.
@MainActor
final class ParentLockerCoreDataStore: ParentLockerStore {

    /// Saves `context`; `created` are the records the save adds (the
    /// Assistant files them into the classroom share, `AssistantSave`).
    typealias Save = @MainActor (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool
    /// Hears that the day's ParentLocker send was recorded and saved, or that
    /// ParentLocker isn't expecting the day's attendance.
    typealias SendRecorded = @MainActor (_ context: NSManagedObjectContext) -> Void

    /// The 9:00 reminder follows a send made with the attendance screen
    /// closed too (Close Arrival's, the backstop's, Siri's or Claude's): it's
    /// withdrawn once the day is sent, or ParentLocker says it expects none.
    static let rescheduleReminder: SendRecorded = { context in
        Task { await FrontDeskEmailReminder.reschedule(in: context) }
    }

    /// The Daybook Assistant is only ever an assistant here, whatever its
    /// membership rows say: with none yet, `currentRole` reads the notebook's
    /// default of lead guide, and the Assistant must never write matches, run
    /// the guide's backstop, or file its send record as the guide's.
    #if ASSISTANT_APP
    static let appRole: CDClassroomMembership.ClassroomRole? = .assistant
    #else
    static let appRole: CDClassroomMembership.ClassroomRole? = nil
    #endif

    let context: NSManagedObjectContext
    private let save: Save
    private let sendRecorded: SendRecorded
    /// This device's role when the app fixes it (`appRole`); nil reads the membership.
    private let fixedRole: CDClassroomMembership.ClassroomRole?

    init(
        context: NSManagedObjectContext,
        save: @escaping Save = { context, _ in context.safeSave() },
        sendRecorded: @escaping SendRecorded = ParentLockerCoreDataStore.rescheduleReminder,
        fixedRole: CDClassroomMembership.ClassroomRole? = ParentLockerCoreDataStore.appRole
    ) {
        self.context = context
        self.save = save
        self.sendRecorded = sendRecorded
        self.fixedRole = fixedRole
    }

    /// Who this device is, for ParentLocker.
    var role: CDClassroomMembership.ClassroomRole {
        fixedRole ?? CDClassroomMembership.currentRole(in: context)
    }

    func day(_ day: Date, withChildren: Bool) -> ParentLockerDay {
        let start = AppCalendar.startOfDay(day)
        let records = records(on: start)
        let settings = AttendanceEmailLog.settings(in: context)
        // The day's sends and its "not expected" note, in one read.
        let channels = AttendanceEmailLog.channels(on: start, in: context)
        var result = ParentLockerDay(
            method: settings?.sendMethod ?? .email,
            site: AttendanceEmailLog.parentLockerHost(settings?.parentLockerSite),
            role: role,
            isSchoolDay: isSchoolDay(start),
            arrivalClosed: records.contains(where: AttendanceDeduplication.isAutomaticAbsence),
            sentToParentLocker: channels.contains(AttendanceSendMethod.parentLocker.rawValue),
            notExpected: channels.contains(AttendanceEmailLog.notExpectedChannel),
            deadlineMinutes: settings?.deadlineMinutes ?? AttendanceEmailLog.defaultDeadlineMinutes
        )
        guard withChildren else { return result }
        result.children = roll(on: start, recordStudentIDs: Set(records.map(\.studentID)))
            .compactMap { ParentLockerPlanner.Child($0) }
        // The record the grid and reports read (`ParentLockerPlanner.dayMarks`).
        for record in records.deduplicatedPerStudentDay() {
            if let id = UUID(uuidString: record.studentID) { result.marks[id] = ParentLockerPlanner.DayMark(record) }
        }
        return result
    }

    var site: String {
        AttendanceEmailLog.parentLockerHost(AttendanceEmailLog.settings(in: context)?.parentLockerSite)
    }

    func children(inRecords records: [NSManagedObjectID], on day: Date) -> Set<UUID> {
        guard !records.isEmpty else { return [] }
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "SELF IN %@ AND date == %@", records, AppCalendar.startOfDay(day) as NSDate
        )
        scopeToClassroom(request)
        return Set(context.safeFetch(request).compactMap { UUID(uuidString: $0.studentID) })
    }

    func marks(of children: Set<UUID>, on day: Date) -> [UUID: ParentLockerPlanner.DayMark] {
        guard !children.isEmpty else { return [:] }
        return ParentLockerPlanner.dayMarks(on: day, for: children, in: context)
    }

    func recordSend(on day: Date) -> Bool {
        let send = AttendanceEmailLog.recordSend(on: day, role: role, channel: .parentLocker, in: context)
        guard save(context, [send]) else { return false }
        sendRecorded(context)
        return true
    }

    /// Once a day: a second run that finds it again notes nothing.
    func noteNotExpected(on day: Date) {
        guard !AttendanceEmailLog.isNotExpected(on: day, in: context) else { return }
        let note = AttendanceEmailLog.recordNotExpected(on: day, role: role, in: context)
        guard save(context, [note]) else { return }
        sendRecorded(context)
    }

    func writeMatches(_ matches: [UUID: String?]) -> Bool {
        guard !matches.isEmpty, role == .leadGuide else { return false }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(matches.keys))
        var changed = false
        for student in context.safeFetch(request) {
            guard let id = student.id, let wanted = matches[id] else { continue }
            let value = wanted?.trimmingCharacters(in: .whitespaces)
            let stored = value?.isEmpty == false ? value : nil
            if student.parentLockerID != stored {
                student.parentLockerID = stored
                changed = true
            }
        }
        // A pick moves that ParentLocker child: whoever else held it lets go,
        // so one child's mark never goes out for two of ours.
        let picked = matches.values.compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !ParentLockerPlanner.isNotMatched($0) }
        if !picked.isEmpty {
            let holders = CDFetchRequest(CDStudent.self)
            holders.predicate = NSPredicate(
                format: "parentLockerID IN %@ AND NOT (id IN %@)", picked, Array(matches.keys)
            )
            for student in context.safeFetch(holders) {
                student.parentLockerID = nil
                changed = true
            }
        }
        return changed ? save(context, []) : true
    }

    // MARK: - Reads

    /// Whether `start` is a school day by the guide's calendar. In the
    /// Assistant, by the classroom share's days off alone, as Siri reads it
    /// (`SiriHost.isSchoolDay`): the private store can hold a notebook of her
    /// own, whose days off aren't the class's.
    private func isSchoolDay(_ start: Date) -> Bool {
        #if ASSISTANT_APP
        SiriHost.isSchoolDay(start, in: context)
        #else
        SchoolDayChecker.isSchoolDay(start, using: context)
        #endif
    }

    /// The day's records, every copy (the dedup reads them all).
    private func records(on start: Date) -> [CDAttendanceRecord] {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "date == %@", start as NSDate)
        scopeToClassroom(request)
        return context.safeFetch(request)
    }

    /// The day's roll, as the grids show it (`AttendanceRoster`): a record
    /// puts a child on it whatever their dates say, test students are left
    /// out, and a child who synced in twice counts once.
    private func roll(on start: Date, recordStudentIDs: Set<String>) -> [CDStudent] {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = AttendanceRoster.predicate(on: start, recordStudentIDs: recordStudentIDs)
        scopeToClassroom(request)
        var seen = Set<UUID>()
        return TestStudentsFilter.filterVisible(context.safeFetch(request)).filter { student in
            guard let id = student.id else { return false }
            return seen.insert(id).inserted
        }
    }

    /// In the Assistant, only the classroom share, as the roll reads it
    /// (`AssistantDayRoll`): on an Apple Account that also keeps a notebook of
    /// its own, the private store holds that notebook's children and marks.
    private func scopeToClassroom<T>(_ request: NSFetchRequest<T>) {
        #if ASSISTANT_APP
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        #endif
    }
}
