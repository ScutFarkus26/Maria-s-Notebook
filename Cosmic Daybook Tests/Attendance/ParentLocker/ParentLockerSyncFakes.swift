import Foundation
import CoreData
import Synchronization
@testable import CosmicDaybook

// Stand-ins for everything `ParentLockerSync` is handed: a ParentLocker site
// in memory (two classes, made-up children), its transport, a clock moved by
// hand, a keychain, a store and a sign-in. Nothing touches the network, the
// real Keychain or the app's preferences.

// MARK: - Clock

/// Time moves only when a test says. The sync's own wake never fires: tests
/// run what's due with `runDue()` after moving the clock.
nonisolated final class FakeParentLockerClock: ParentLockerClock {
    private let current: Mutex<Date>

    init(_ start: Date) { current = Mutex(start) }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }

    func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(1_000_000))
    }
}

// MARK: - Keychain

nonisolated final class FakeParentLockerSecrets: ParentLockerSecrets {
    private struct Items {
        var credential: ParentLockerKeychain.Credential?
        /// When the password was last saved: each save is a second later.
        var modified: Date?
        var cookies: [ParentLockerCookie] = []
        /// The Keychain's answer to reading or deleting the password, when it
        /// isn't the item itself (locked since restart, say).
        var trouble: ParentLockerKeychain.KeychainError?
    }

    private let items = Mutex(Items())

    init(password: String? = "made-up-password", cookie: String? = "good") {
        items.withLock { items in
            items.credential = password.map { .init(email: "guide@school.test", password: $0) }
            items.modified = password.map { _ in Date(timeIntervalSinceReferenceDate: 0) }
            items.cookies = cookie.map {
                [ParentLockerCookie(name: "PHPSESSID", value: $0, domain: FakeParentLocker.host)]
            } ?? []
        }
    }

    var savedCookies: [ParentLockerCookie] { items.withLock { $0.cookies } }

    /// From now on, reading or deleting the password fails with `trouble`.
    func fail(with trouble: ParentLockerKeychain.KeychainError?) { items.withLock { $0.trouble = trouble } }

    func credential(site: String) throws -> ParentLockerKeychain.Credential? {
        try items.withLock { items in
            if let trouble = items.trouble { throw trouble }
            return items.credential
        }
    }
    func hasPassword(site: String) throws -> Bool {
        try items.withLock { items in
            if let trouble = items.trouble { throw trouble }
            return items.credential != nil
        }
    }
    func passwordModified(site: String) throws -> Date? {
        try items.withLock { items in
            if let trouble = items.trouble { throw trouble }
            return items.modified
        }
    }
    func savePassword(_ credential: ParentLockerKeychain.Credential, site: String) throws {
        items.withLock { items in
            items.credential = credential
            items.modified = (items.modified ?? Date(timeIntervalSinceReferenceDate: 0)).addingTimeInterval(1)
        }
    }
    func deletePassword(site: String) throws {
        try items.withLock { items in
            if let trouble = items.trouble { throw trouble }
            items.credential = nil
            items.modified = nil
        }
    }
    func cookies(site: String) throws -> [ParentLockerCookie] { items.withLock { $0.cookies } }
    func saveCookies(_ cookies: [ParentLockerCookie], site: String) throws { items.withLock { $0.cookies = cookies } }
    func deleteCookies(site: String) throws { items.withLock { $0.cookies = [] } }
}

// MARK: - The site

/// ParentLocker in memory: two daily classes and their children, the marks
/// each holds, and every request and save made of it.
@MainActor
final class FakeParentLocker {

    nonisolated static let host = "school.parentlocker.test"

    struct Kid {
        let studentID: Int
        let first: String
        let last: String
        var alternate = ""
        let course: ParentLockerCourse
        var markID: String?
        var comment = ""
        var locked = false
    }

    static let middle = ParentLockerCourse(
        courseID: 5101, name: "Girls Middle School", period: 1, attendanceReportID: "880001"
    )
    static let upper = ParentLockerCourse(
        courseID: 5102, name: "Upper Elementary Girls", period: 1, attendanceReportID: "880002"
    )

    /// The classes as the page lists them: today's, or another day's with
    /// that day's own report ids (77…, where today's are 88…).
    static func courses(on day: Date?) -> [ParentLockerCourse] {
        guard day != nil else { return [middle, upper] }
        return [middle, upper].map { course in
            ParentLockerCourse(
                courseID: course.courseID, name: course.name, period: course.period,
                attendanceReportID: "77" + course.attendanceReportID.dropFirst(2)
            )
        }
    }

    static let marks = [
        ParentLockerMark(id: "701", name: "Present", type: "present"),
        ParentLockerMark(id: "702", name: "Late", type: "late"),
        ParentLockerMark(id: "703", name: "Absent", type: "absent")
    ]

    var kids: [Kid] = [
        Kid(studentID: 40001, first: "Wren", last: "Halloway", course: middle),
        Kid(studentID: 40002, first: "Juniper", last: "Ashby", alternate: "June", course: middle),
        Kid(studentID: 40003, first: "Marisol", last: "Peña", course: middle),
        Kid(studentID: 41002, first: "Odile", last: "Brandt", course: upper),
        Kid(studentID: 41004, first: "Bea", last: "Marchetti", course: upper)
    ]

    /// Every request, in order: "courses", "roster 5101", "save 5101".
    var requests: [String] = []
    var saves: [ParentLockerPlanner.Batch] = []
    /// How many more requests fail as unreachable.
    var failuresLeft = 0
    /// Only requests carrying this cookie value are signed in.
    var goodCookie = "good"
    var password = "made-up-password"
    var signIns = 0
    /// How many times the sign-in form lets other work run before it
    /// answers, as the real web view does.
    var signInYields = 0
    /// What the next saves report as changed by someone else.
    var conflicts: [ParentLockerSaveReply.Conflict] = []
    /// The form puts a page of its own in the way (new terms, a reset).
    var signInNeedsYou = false
    /// Today's page lists every class as not expecting attendance.
    var notExpectedToday = false

    func mark(_ studentID: Int) -> String? { kids.first { $0.studentID == studentID }?.markID }

    func setMark(_ studentID: Int, _ markID: String?) {
        if let index = kids.firstIndex(where: { $0.studentID == studentID }) { kids[index].markID = markID }
    }

    /// The sign-in the site's form would give.
    func signIn(_ credential: ParentLockerKeychain.Credential) throws -> [ParentLockerCookie] {
        signIns += 1
        if signInNeedsYou { throw ParentLockerSignInError.needsYou }
        guard credential.password == password else { throw ParentLockerSignInError.passwordRefused }
        return [ParentLockerCookie(name: "PHPSESSID", value: goodCookie, domain: Self.host)]
    }

    fileprivate func check(_ cookies: [ParentLockerCookie]) throws {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw ParentLockerError.unreachable
        }
        guard cookies.contains(where: { $0.value == goodCookie }) else { throw ParentLockerError.signedOut }
    }

    fileprivate func roster(for course: ParentLockerCourse) -> ParentLockerRoster {
        let students = kids.filter { $0.course.courseID == course.courseID }.compactMap { kid in
            ParentLockerRosterStudent(json: .object([
                "student_id": .int(kid.studentID),
                "first_name": .string(kid.first),
                "last_name": .string(kid.last),
                "alternate_name": .string(kid.alternate),
                "attendance": .object([
                    "attendance_code": .object(["id": .string(kid.markID ?? "")]),
                    "attendance_code_id": .string(kid.markID ?? ""),
                    "comment": .string(kid.comment),
                    "confirmed": .bool(kid.markID != nil),
                    "is_locked": .bool(kid.locked),
                    "student_id": .int(kid.studentID),
                    "course_id": .int(course.courseID)
                ])
            ]))
        }
        return ParentLockerRoster(course: course, students: students, marks: Self.marks)
    }

    fileprivate func apply(_ batch: ParentLockerPlanner.Batch) -> ParentLockerSaveReply {
        saves.append(batch)
        for entry in batch.entries {
            guard let index = kids.firstIndex(where: { String($0.studentID) == entry.studentID }) else { continue }
            kids[index].markID = entry.attendance["attendance_code"]?["id"]?.stringValue
            if let comment = entry.attendance["comment"]?.stringValue { kids[index].comment = comment }
        }
        defer { conflicts = [] }
        return ParentLockerSaveReply(conflicts: conflicts)
    }
}

/// The site's three requests, against `FakeParentLocker`.
nonisolated struct FakeParentLockerTransport: ParentLockerTransport {
    let site: FakeParentLocker
    let cookies: [ParentLockerCookie]

    /// "courses" for today's page, "courses 2026-10-9" for another day's.
    func courses(on day: Date?) async throws -> [ParentLockerCourse] {
        try await MainActor.run {
            site.requests.append(day.map { "courses " + ParentLockerPlanner.dateText($0) } ?? "courses")
            try site.check(cookies)
            guard day == nil, site.notExpectedToday else { return FakeParentLocker.courses(on: day) }
            return FakeParentLocker.courses(on: nil).map { course in
                ParentLockerCourse(
                    courseID: course.courseID, name: course.name, period: course.period,
                    attendanceReportID: course.attendanceReportID, reportStatus: "not_expected"
                )
            }
        }
    }

    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster {
        try await MainActor.run {
            site.requests.append("roster \(course.courseID)")
            try site.check(cookies)
            return site.roster(for: course)
        }
    }

    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply {
        try await MainActor.run {
            site.requests.append("save \(batch.course.courseID)")
            try site.check(cookies)
            return site.apply(batch)
        }
    }
}

// MARK: - The notebook

/// One device's notebook: the day as the sync reads it, and what it records.
@MainActor
final class FakeParentLockerStore: ParentLockerStore {
    var state: ParentLockerDay
    var recordedSends: [Date] = []
    var writtenMatches: [[UUID: String?]] = []
    /// The days the sync said ParentLocker isn't expecting attendance.
    var notExpectedDays: [Date] = []

    init(state: ParentLockerDay) { self.state = state }

    var site: String { state.site }

    /// The day as `state` holds it; a send recorded counts for its own day only.
    func day(_ day: Date, withChildren: Bool) -> ParentLockerDay {
        var result = state
        result.sentToParentLocker = state.sentToParentLocker
            || recordedSends.contains { AppCalendar.shared.isDate($0, inSameDayAs: day) }
        if !withChildren {
            result.children = []
            result.marks = [:]
        }
        return result
    }

    func children(inRecords records: [NSManagedObjectID], on day: Date) -> Set<UUID> { [] }

    func marks(of children: Set<UUID>, on day: Date) -> [UUID: ParentLockerPlanner.DayMark] {
        state.marks.filter { children.contains($0.key) }
    }

    func recordSend(on day: Date) -> Bool {
        recordedSends.append(day)
        return true
    }

    func noteNotExpected(on day: Date) {
        notExpectedDays.append(day)
    }

    /// Stores the matches on the children, as the real store does: a pick
    /// clears that ParentLocker child from whoever else held it.
    func writeMatches(_ matches: [UUID: String?]) -> Bool {
        writtenMatches.append(matches)
        let picked = Set(matches.values.compactMap { $0 }.filter { !ParentLockerPlanner.isNotMatched($0) })
        state.children = state.children.map { child in
            let stored: String?
            if let wanted = matches[child.id] {
                stored = wanted
            } else if let held = child.parentLockerID, picked.contains(held) {
                stored = nil
            } else {
                return child
            }
            return ParentLockerPlanner.Child(
                id: child.id, firstName: child.firstName, lastName: child.lastName,
                nickname: child.nickname, parentLockerID: stored
            )
        }
        return true
    }
}

@MainActor
final class FakeParentLockerBackground: ParentLockerBackgroundWork {
    var isHeld = false
    func begin() { isHeld = true }
    func end() { isHeld = false }
}
