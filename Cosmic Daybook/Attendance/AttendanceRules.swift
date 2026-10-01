import Foundation

/// Which part of the morning the taps are for, on one device.
enum AttendancePhase: Equatable {
    /// Children are arriving: a tap marks present.
    case arrival
    /// Arrival has closed: the rest are absent, and a tap marks tardy.
    case late
}

/// The rules both attendance grids run on, apart from their state: what a
/// tap means, what a day allows, who marked a child, and the tallies. Pure,
/// so the tests call them directly. Shared with the Daybook Assistant.
@MainActor
enum AttendanceRules {

    /// What a tap does in `phase`. During Arrival a tap marks present and a
    /// second tap unmarks; during Late a tap turns absent (or unmarked) into
    /// tardy and a second tap turns it back. A present child is left alone
    /// during Late: the long-press menu changes that.
    static func statusAfterTap(from status: AttendanceStatus, in phase: AttendancePhase) -> AttendanceStatus? {
        switch (phase, status) {
        case (.arrival, .present): return .unmarked
        case (.arrival, _): return .present
        case (.late, .tardy): return .absent
        case (.late, .absent), (.late, .unmarked): return .tardy
        case (.late, _): return nil
        }
    }

    /// Whether `status` can be set on `day`. Ahead of the day there's no
    /// arrival to record, so only Absent, or clearing a mark, is allowed.
    /// The intents follow the same rule.
    static func allows(_ status: AttendanceStatus, on day: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        guard calendar.startOfDay(for: day) > calendar.startOfDay(for: now) else { return true }
        return status == .absent || status == .unmarked
    }

    /// The Mac's click: the next status in the cycle that `day` allows, so a
    /// day ahead goes unmarked ↔ absent.
    static func cycle(from status: AttendanceStatus, on day: Date, now: Date = Date()) -> AttendanceStatus {
        var next = status.next()
        while !allows(next, on: day, now: now), next != status {
            next = next.next()
        }
        return next
    }

    /// The statuses a menu offers on `day`.
    static func menuStatuses(on day: Date, now: Date = Date()) -> [AttendanceStatus] {
        [.present, .absent, .tardy, .leftEarly, .unmarked].filter { allows($0, on: day, now: now) }
    }

    /// Who made the mark: "you", another assistant's name, or "your guide"
    /// (the owner's name when CloudKit gives it; the guide's own marks carry
    /// no name). Nil while unmarked, and for old marks made before
    /// attribution existed.
    static func markerName(
        for row: AttendanceRow,
        myRecordName: String?,
        myName: String?,
        guideName: String?
    ) -> String? {
        guard row.status != .unmarked else { return nil }
        switch row.recordedBy {
        case CDClassroomMembership.ClassroomRole.leadGuide.rawValue:
            return guideName ?? "your guide"
        case CDClassroomMembership.ClassroomRole.assistant.rawValue:
            if let id = row.recordedByID, let mine = myRecordName {
                return id == mine ? "you" : (row.recordedByName ?? "another assistant")
            } else if let name = row.recordedByName {
                return name == myName ? "you" : name
            }
            return "an assistant"
        default:
            return nil
        }
    }

    /// "Present at 8:04", "Left Early 8:02 → 1:15", "Absent, Sick", or nil
    /// while unmarked. Marks made on another day carry no time.
    static func markSummary(_ row: AttendanceRow) -> String? {
        guard row.status != .unmarked else { return nil }
        var text = row.status.displayName
        switch row.status {
        case .absent where row.absenceReason != .none:
            text += ", \(row.absenceReason.displayName)"
        case .leftEarly:
            if let arrived = row.markedAt, let left = row.leftAt {
                text += " \(AttendanceClock.string(arrived)) → \(AttendanceClock.string(left))"
            } else if let left = row.leftAt {
                text += " at \(AttendanceClock.string(left))"
            }
        case .present, .tardy:
            if let markedAt = row.markedAt { text += " at \(AttendanceClock.string(markedAt))" }
        default:
            break
        }
        return text
    }

    /// "8:02 → 1:15", "left 1:15", or nil when neither time is known.
    static func leftEarlyTimes(_ row: AttendanceRow) -> String? {
        switch (row.markedAt, row.leftAt) {
        case let (arrived?, left?): return "\(AttendanceClock.string(arrived)) → \(AttendanceClock.string(left))"
        case let (nil, left?): return "left \(AttendanceClock.string(left))"
        default: return nil
        }
    }

    /// How far back a welcome back counts; a child away longer is "15+".
    static let welcomeBackLookback = 15

    /// "Back after 4 days", "Back after 15+ days".
    static func welcomeBackPhrase(daysAway: Int) -> String {
        daysAway >= welcomeBackLookback
            ? "Back after \(welcomeBackLookback)+ days"
            : "Back after \(daysAway) days"
    }

    /// "19 here (1 late) · 2 absent · 1 not marked", leaving out what's
    /// zero. Late and left early are children who came in, so they count as
    /// here (marking a child late moves "here" up), and the brackets say how
    /// many of those were.
    static func tally(_ rows: [AttendanceRow]) -> String {
        counts(rows, breakdown: true)
    }

    /// The tally when the full one won't fit: "3 here · 1 absent · 18 not
    /// marked", without the late and left-early brackets, since the tiles
    /// already say which.
    static func shortTally(_ rows: [AttendanceRow]) -> String {
        counts(rows, breakdown: false)
    }

    private static func counts(_ rows: [AttendanceRow], breakdown: Bool) -> String {
        let count = { (status: AttendanceStatus) in rows.count { $0.status == status } }
        var here = "\(rows.count(where: \.isHere)) here"
        let ofThem = [(count(.tardy), "late"), (count(.leftEarly), "left early")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        if breakdown, !ofThem.isEmpty {
            here += " (\(ofThem.joined(separator: ", ")))"
        }
        let parts = [
            (rows.count(where: \.isHere), here),
            (count(.absent), "\(count(.absent)) absent"),
            (count(.unmarked), "\(count(.unmarked)) not marked")
        ]
        return parts.filter { $0.0 > 0 }.map(\.1).joined(separator: " · ")
    }

    /// The line once everyone's marked: "Everyone's here · 8:14" (the time
    /// only today), or "All marked · 20 here, 2 home". `everyone` words the
    /// first case ("Everyone's here for day 100").
    static func completionText(
        _ rows: [AttendanceRow],
        at time: Date?,
        everyone: String = "Everyone's here"
    ) -> String {
        let here = rows.count(where: \.isHere)
        let home = rows.count { $0.status == .absent }
        guard home > 0 else {
            return time.map { "\(everyone) · \(AttendanceClock.string($0))" } ?? everyone
        }
        return "All marked · \(here) here, \(home) home"
    }
}
