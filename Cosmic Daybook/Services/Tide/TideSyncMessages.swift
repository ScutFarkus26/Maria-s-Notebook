// TideSyncMessages.swift
// Every sentence the Tide sharing shows, in one place.

import Foundation

/// What Settings and the to-do screens say about sharing to-dos with Tide, in
/// everyday words (project rule: no codes, addresses or tool names on screen;
/// those go under Details).
nonisolated enum TideSyncMessages {
    static let off = "Off. Turn it on to share to-dos with Tide."
    static let needsAddress = "Paste Tide's connection address to start. In Tide, open Settings › Claude and copy it."
    static let notOnThisDevice = "To-dos go to and from Tide from the notebook on your Mac, while Tide is open "
        + "there. What you change here goes across the next time the Mac's notebook is open."
    static let testCopy = "This is a test copy of the notebook, so it doesn't share to-dos with Tide. "
        + "The copy in Applications does."
    static let tideNotRunning = "Tide isn't open on this Mac. To-dos will go across when it is."
    static let tideTimedOut = "Tide didn't answer in time. To-dos will go across when it does."
    static let tideStillOpening = "Tide is still opening. To-dos will go across in a moment."
    static let tokenRefused = "Tide didn't accept the saved connection. Copy the address from Tide's "
        + "Settings › Claude and paste it here again."
    static let unexpectedReply = "Couldn't share to-dos with Tide just now. It will try again in a few minutes."
    static let syncing = "Sharing to-dos with Tide…"
    static let upToDate = "Up to date with Tide."
    static let waitingForOK = "Check the matches below, then press Link and Start. Nothing goes across until you do."
    static let noArea = "Tide has no My Classrooms area, so there's nothing to share yet."
    static let destinationGone = "The Tide list for new to-dos isn't there any more. Pick another one below. "
        + "Ticks still go across."
    static let saveFailed = "Couldn't save the to-dos from Tide in the notebook. It will try again in a few minutes."
    static let paused = "Paused while this Mac saves energy (Low Power Mode, or it's running hot). "
        + "Sync Now still shares to-dos."
    static let readFailed = "Couldn't read the saved Tide connection on this Mac. Paste the address again."

    /// Said when Tide refused some to-dos the notebook sent.
    static func notSent(_ titles: [String]) -> String {
        guard let first = titles.first else { return upToDate }
        if titles.count == 1 {
            return "Tide wouldn't take “\(first)”. Change it here and it will try again."
        }
        return "Tide wouldn't take \(titles.count) to-dos, among them “\(first)”. "
            + "Change them here and it will try again."
    }

    /// Said when Tide wouldn't take a change made here to a to-do made there.
    static func notCarried(_ titles: [String]) -> String {
        guard let first = titles.first else { return upToDate }
        if titles.count == 1 {
            return "Tide wouldn't take the change to “\(first)”, so it's changed here but not in Tide."
        }
        return "Tide wouldn't take the changes to \(titles.count) to-dos, among them “\(first)”, "
            + "so they're changed here but not in Tide."
    }

    /// Said when a to-do made in Tide was given a due date here that has
    /// already passed: Tide only takes one still ahead.
    static func pastDue(_ titles: [String]) -> String {
        guard let first = titles.first else { return upToDate }
        let more = titles.count > 1 ? " and \(titles.count - 1) more" : ""
        return "Tide only takes a due date that's still ahead, so the date on “\(first)”\(more) "
            + "is changed here but not in Tide."
    }

    /// Said while a tick can't be aimed: Tide's list has more than one action
    /// with the to-do's words (a weekly to-do sent each week, say).
    static func notTicked(_ titles: [String]) -> String {
        guard let first = titles.first else { return upToDate }
        let more = titles.count > 1 ? " and \(titles.count - 1) more" : ""
        return "Tide can't tell which “\(first)”\(more) to tick off: its list has more than one with those words. "
            + "Tick it off in Tide, and the notebook will follow."
    }

    /// Said when the heading new to-dos go under is gone from the Tide list.
    static func headingGone(_ heading: String?, list: String) -> String {
        let name = heading.map { "“\($0)”" } ?? "for new to-dos"
        return "The heading \(name) isn't in Tide's \(list) list any more. Pick another in Settings."
    }

    /// Said when some to-dos wait for the next run.
    static let nextTry = "Some to-dos will go across on the next try, in a few minutes."

    /// The line in a to-do's editor once it is linked with Tide. The editor
    /// can't tell which to-dos were made in Tide (the Mac keeps that), so it
    /// says both.
    static func linkedNote(listName: String) -> String {
        "In Tide's \(listName) list. Ticking it off here ticks it off in Tide. If it was made in Tide, "
            + "a new title or due date here goes to Tide too; if it was made here, Tide keeps its own wording."
    }

    /// Settings' summary of what the sharing does.
    static let explainer = "Every open to-do goes to Tide except the automatic work check-ins, and the to-dos "
        + "in the Tide lists you pick show here. Ticking one off in either app ticks it off in the other; "
        + "unticking doesn't carry. Once a to-do from here is in Tide, Tide keeps its wording; for one made "
        + "in Tide, a new title or due date in either app goes to the other. Checklists, Someday "
        + "and linked work stay in the notebook. The repeat rule stays here; each new one goes to Tide."
}
