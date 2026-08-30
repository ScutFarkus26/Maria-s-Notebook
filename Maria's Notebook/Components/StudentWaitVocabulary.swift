// StudentWaitVocabulary.swift
// What the workspace's left-hand column says, and which age thresholds it
// colours itself by.
//
// Both halves of Lessons & Work put the same column down their left edge: the
// children, ordered by how long they have gone without the guide. Only the
// wording and the thresholds differ, and they differ in exactly the way the
// halves themselves do — a presentation ages on the `LessonAge` settings, a
// piece of work on the `WorkAge` ones, and the column has to match the cards
// beside it or the same colour would mean two things on one screen.
//
// Holding both wordings in one file is deliberate. They have to read as
// siblings, and they will only keep reading as siblings if changing one puts
// the other in front of you.

import Foundation

/// The five settings keys an age bar is drawn from. The app already ships two
/// families of them; this only names which family a column belongs to.
struct StudentAgeKeys: Sendable {
    let warningDays: String
    let overdueDays: String
    let freshColorHex: String
    let warningColorHex: String
    let overdueColorHex: String

    /// The thresholds the presentation cards and pills use.
    static let lessons = StudentAgeKeys(
        warningDays: UserDefaultsKeys.lessonAgeWarningDays,
        overdueDays: UserDefaultsKeys.lessonAgeOverdueDays,
        freshColorHex: UserDefaultsKeys.lessonAgeFreshColorHex,
        warningColorHex: UserDefaultsKeys.lessonAgeWarningColorHex,
        overdueColorHex: UserDefaultsKeys.lessonAgeOverdueColorHex
    )

    /// The thresholds the work cards use.
    static let work = StudentAgeKeys(
        warningDays: UserDefaultsKeys.workAgeWarningDays,
        overdueDays: UserDefaultsKeys.workAgeOverdueDays,
        freshColorHex: UserDefaultsKeys.workAgeFreshColorHex,
        warningColorHex: UserDefaultsKeys.workAgeWarningColorHex,
        overdueColorHex: UserDefaultsKeys.workAgeOverdueColorHex
    )
}

/// How one column of children describes itself.
struct StudentWaitVocabulary: Sendable {
    /// The column's own heading and icon.
    let title: String
    let systemImage: String
    /// The metadata line for a child there is nothing to measure for.
    let uncounted: String
    /// The metadata line for a child seen today.
    let today: String
    /// Read after the number of days, for VoiceOver.
    let daysAgoSuffix: String
    /// What tapping a row does.
    let selectionHint: String
    /// Which age settings the bar down each row is coloured by.
    let ageKeys: StudentAgeKeys

    /// Presentations: how long since this child was last taught.
    static let lessons = StudentWaitVocabulary(
        title: "Waiting Longest",
        systemImage: "clock.arrow.circlepath",
        uncounted: "Never taught",
        today: "Taught today",
        daysAgoSuffix: "school days since a lesson",
        selectionHint: "Shows only lessons ready for this child",
        ageKeys: .lessons
    )

    /// Work: how long since the guide last looked at anything of this child's.
    ///
    /// "No open work" is the counterpart of "Never taught" — the case the grid
    /// beside the column cannot show at all, because a child with nothing has
    /// no card.
    static let work = StudentWaitVocabulary(
        title: "Quiet Longest",
        systemImage: "hourglass",
        uncounted: "No open work",
        today: "Checked today",
        daysAgoSuffix: "school days since their work was checked",
        selectionHint: "Shows only this child's work",
        ageKeys: .work
    )

    /// The metadata line under a child's name.
    func detail(forDays days: Int?) -> String {
        guard let days else { return uncounted }
        switch days {
        case 0: return today
        case 1: return "1 school day ago"
        default: return "\(days) school days ago"
        }
    }

    /// The same thing said in full, for VoiceOver and for the phone's strip,
    /// where the number is abbreviated to "12d".
    func spokenDetail(forDays days: Int?) -> String {
        guard let days else { return uncounted.lowercased() }
        return "\(days) \(daysAgoSuffix)"
    }
}
