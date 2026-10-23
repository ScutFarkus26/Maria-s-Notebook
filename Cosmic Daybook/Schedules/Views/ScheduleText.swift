// ScheduleText.swift
// The words the Schedules page and Today's Schedule section put on a block:
// a room in a sentence ("in the adolescent room"), who teaches it, the
// "1 change today" chip, and the line a lane's lessons get. Plain functions
// over the resolver's values, so they're tested without a screen.

import Foundation

enum ScheduleText {

    /// "in the adolescent room", "in our class": a room's name as it reads in
    /// a sentence. A name typed in sentence case ("Adolescent room") is
    /// lowered; one with capitals inside ("Beit Midrash") is kept as typed.
    static func inRoom(_ name: String) -> String {
        let name = name.trimmed()
        guard !name.isEmpty else { return "in the other room" }
        let rest = name.dropFirst()
        let spoken = rest == rest.lowercased() ? name.prefix(1).lowercased() + rest : name
        let lowered = spoken.lowercased()
        if lowered.hasPrefix("our ") || lowered.hasPrefix("the ") { return "in \(spoken)" }
        return "in the \(spoken)"
    }

    /// "In the adolescent room · Math": a turn as its teacher's lane shows it.
    static func turnTitle(room: String, title: String) -> String {
        let place = inRoom(room)
        let heading = place.prefix(1).uppercased() + place.dropFirst()
        let title = title.trimmed()
        return title.isEmpty ? heading : "\(heading) · \(title)"
    }

    /// "Your turn in the adolescent room · Math": the guide's turn on Today.
    static func yourTurnTitle(room: String, title: String) -> String {
        let title = title.trimmed()
        let turn = "Your turn \(inRoom(room))"
        return title.isEmpty ? turn : "\(turn) · \(title)"
    }

    /// Who teaches a room's block: a person lane's name, or the name typed
    /// for anyone else. Nil when no one is named.
    static func teacher(of values: TimetableBlockValues, lanes: [UUID: TimetableLaneSnapshot]) -> String? {
        if let id = values.teacherLaneID, let lane = lanes[id] {
            let name = lane.name.trimmed()
            return name.isEmpty ? nil : name
        }
        let typed = values.teacherName.trimmed()
        return typed.isEmpty ? nil : typed
    }

    /// "1 change today", "3 changes": the chip in the header. Nil on a day
    /// with no change.
    static func changeChip(count: Int, isToday: Bool) -> String? {
        guard count > 0 else { return nil }
        let changes = count == 1 ? "1 change" : "\(count) changes"
        return isToday ? "\(changes) today" : changes
    }

    /// "2 days changed": the Week view's chip. Nil when no day changed.
    static func weekChangeChip(days: Int) -> String? {
        guard days > 0 else { return nil }
        return days == 1 ? "1 day changed" : "\(days) days changed"
    }

    /// "Week of October 26 · Vayera": the Week view's line, with the parsha
    /// read that week when there is one.
    static func weekLine(monday: Date) -> String {
        var parts = ["Week of \(monday.formatted(.dateTime.month(.wide).day()))"]
        if let key = HebrewParshaService.currentParshaKey(on: monday) {
            parts.append(HebrewParshaService.displayName(forKey: key))
        }
        return parts.joined(separator: " · ")
    }

    /// "Morning lessons", "Afternoon lessons": a half's ordered list.
    static func halfListTitle(_ half: ScheduleDayHalf) -> String {
        switch half {
        case .morning: "Morning lessons"
        case .afternoon: "Afternoon lessons"
        }
    }

    /// "Maya S, Eli B": children by their short names, any the notebook
    /// doesn't know left out; past four, "Maya S, Eli B, Noah L and 2 more".
    static func children(_ ids: [String], name: (String) -> String?) -> String? {
        let names = ids.compactMap(name)
        guard !names.isEmpty else { return nil }
        if names.count > 4 { return "\(names.prefix(3).joined(separator: ", ")) and \(names.count - 3) more" }
        return names.joined(separator: ", ")
    }

    /// A lesson's name, or a plain stand-in when the plan has none.
    static func lessonTitle(_ lesson: ScheduleDay.Lesson) -> String {
        let title = lesson.snapshot.title?.trimmed() ?? ""
        return title.isEmpty ? "A planned lesson" : title
    }

    /// What a block says about its day: "Today only" for a one-off,
    /// "Changed today" for a block with that day's own values.
    static func dayMark(_ block: ScheduleDay.Block, isToday: Bool) -> String? {
        if block.isOneOff { return isToday ? "Today only" : "This day only" }
        if block.isChanged { return isToday ? "Changed today" : "Changed this day" }
        return nil
    }

    /// "Morah Devora is out today".
    static func outLine(_ name: String, isToday: Bool) -> String {
        "\(name.trimmed()) is out \(isToday ? "today" : "this day")"
    }
}
