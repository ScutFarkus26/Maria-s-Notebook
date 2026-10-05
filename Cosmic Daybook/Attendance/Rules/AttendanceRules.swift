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
    /// during Late, and a child who left early in either phase: the
    /// long-press menu changes those (Back in Class for a child who
    /// returns), so a stray tap can't wipe out the day's times.
    static func statusAfterTap(from status: AttendanceStatus, in phase: AttendancePhase) -> AttendanceStatus? {
        switch (phase, status) {
        case (_, .leftEarly): return nil
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

    /// The statuses a menu offers on `day`.
    static func menuStatuses(on day: Date, now: Date = Date()) -> [AttendanceStatus] {
        [.present, .absent, .tardy, .leftEarly, .unmarked].filter { allows($0, on: day, now: now) }
    }

    /// Who made the mark: "you", another assistant's name, or "your guide"
    /// (the owner's name when CloudKit gives it; the guide's own marks carry
    /// no name). Nil while unmarked, and for old marks made before
    /// attribution existed. `viewerRole` is whose screen it is.
    static func markerName(
        for row: AttendanceRow,
        myRecordName: String?,
        myName: String?,
        guideName: String?,
        viewerRole: CDClassroomMembership.ClassroomRole = .leadGuide
    ) -> String? {
        guard row.status != .unmarked else { return nil }
        // A stand-in such as `__defaultOwner__`, on either side, is no ID.
        let markedByID = ClassroomIdentity.realRecordName(row.recordedByID)
        let myRecordName = ClassroomIdentity.realRecordName(myRecordName)
        switch row.recordedBy {
        case CDClassroomMembership.ClassroomRole.leadGuide.rawValue:
            return guideName ?? "your guide"
        case CDClassroomMembership.ClassroomRole.assistant.rawValue:
            if let id = markedByID, let mine = myRecordName {
                return id == mine ? "you" : (row.recordedByName ?? "another assistant")
            } else if viewerRole == .assistant, row.recordedByName == myName,
                      markedByID == nil || markedByID == myRecordName {
                // Her own mark from a phone with no record name yet (or the
                // Sample Class, which has neither a name nor an id), read as
                // the front-desk line reads her send (`AttendanceEmailLog.Send`).
                return "you"
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

    // MARK: - Back in Class

    /// Whether the menu offers Back in Class: the child is marked Left Early.
    static func allowsBack(for row: AttendanceRow) -> Bool {
        row.status == .leftEarly
    }

    /// "out 11:15–12:40": a child who left early and came back, or "out at
    /// 11:15" when the return has no time (brought back on a later day).
    /// Nil for anyone who hasn't been out and back. A trip needs `leftAt` on
    /// a present or late mark, which only Back in Class leaves; an older
    /// build's mark clears `leftAt`, so a stale `returnedAt` never shows.
    static func tripText(_ row: AttendanceRow) -> String? {
        guard row.status == .present || row.status == .tardy, let left = row.leftAt else { return nil }
        guard let back = row.returnedAt else { return "out at \(AttendanceClock.string(left))" }
        return "out \(AttendanceClock.string(left))–\(AttendanceClock.string(back))"
    }

    /// "8:02 → 1:15", "left 1:15", or nil when neither time is known.
    static func leftEarlyTimes(_ row: AttendanceRow) -> String? {
        switch (row.markedAt, row.leftAt) {
        case let (arrived?, left?): return "\(AttendanceClock.string(arrived)) → \(AttendanceClock.string(left))"
        case let (nil, left?): return "left \(AttendanceClock.string(left))"
        default: return nil
        }
    }

    // MARK: - Early pickup

    /// The pickup time still to come for `row`: its `leavesAt`, unless the
    /// child is absent or has already been marked Left Early (then the plan
    /// is moot, or the tile shows when they actually went).
    static func pendingPickup(_ row: AttendanceRow) -> Date? {
        switch row.status {
        case .absent, .leftEarly: return nil
        case .present, .tardy, .unmarked: return row.leavesAt
        }
    }

    /// "leaves 1:30", while a pickup is still to come.
    static func pickupText(_ row: AttendanceRow) -> String? {
        pendingPickup(row).map { "leaves \(AttendanceClock.string($0))" }
    }

    /// Whether the menu offers Leaving Early… for `row` on `day`: today or a
    /// day ahead (a parent's note for Friday), never a day gone by, and not
    /// for a child absent or already gone home.
    static func allowsPickup(for row: AttendanceRow, on day: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        guard calendar.startOfDay(for: day) >= calendar.startOfDay(for: now) else { return false }
        return row.status != .absent && row.status != .leftEarly
    }

    /// The time the pickup sheet starts on: the one already set, else the
    /// next half hour today (noon on a day ahead), on `day`.
    static func suggestedPickup(for row: AttendanceRow, on day: Date, now: Date = Date()) -> Date {
        if let set = row.leavesAt { return set }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard calendar.isDate(day, inSameDayAs: now) else {
            return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        }
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let rounded = (minutes / 30 + 1) * 30
        return calendar.date(byAdding: .minute, value: rounded, to: start) ?? now
    }

    /// `time`'s hour and minute on `day`: a picker's answer, put on the
    /// record's own day.
    static func pickup(_ time: Date, on day: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), to: start)
            ?? time
    }

    /// How far back a welcome back counts; a child away longer is "15+".
    static let welcomeBackLookback = 15

    /// "Back after 4 days", "Back after 15+ days".
    static func welcomeBackPhrase(daysAway: Int) -> String {
        daysAway >= welcomeBackLookback
            ? "Back after \(welcomeBackLookback)+ days"
            : "Back after \(daysAway) days"
    }

    /// "17 here": who's in the room now, late arrivals included. A child
    /// who left early is no longer counted in it. The count's large line
    /// (`AttendanceHereCount`).
    static func hereLine(_ rows: [AttendanceRow]) -> String {
        "\(rows.count(where: \.isInRoom)) here"
    }

    /// "1 late · 1 left early · 2 absent · 1 not marked", leaving out what's
    /// zero, or nil when there's nothing to add: the small line under
    /// `hereLine`. Late is the part of here that came late.
    static func detailLine(_ rows: [AttendanceRow]) -> String? {
        let parts: [(AttendanceStatus, String)] = [
            (.tardy, "late"), (.leftEarly, "left early"), (.absent, "absent"), (.unmarked, "not marked")
        ]
        let text = parts.compactMap { status, word in
            let count = rows.count { $0.status == status }
            return count > 0 ? "\(count) \(word)" : nil
        }
        return text.isEmpty ? nil : text.joined(separator: " · ")
    }

    /// The line once everyone's marked: "Everyone's here · 8:14" (the time
    /// only today), or "All marked · 17 here, 3 home", where home counts the
    /// absent and anyone who has left early. `everyone` words the first case
    /// ("Everyone's here for day 100").
    static func completionText(
        _ rows: [AttendanceRow],
        at time: Date?,
        everyone: String = "Everyone's here"
    ) -> String {
        let here = rows.count(where: \.isInRoom)
        let home = rows.count { $0.status == .absent || $0.status == .leftEarly }
        guard home > 0 else {
            return time.map { "\(everyone) · \(AttendanceClock.string($0))" } ?? everyone
        }
        return "All marked · \(here) here, \(home) home"
    }
}
