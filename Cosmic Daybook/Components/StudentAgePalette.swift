// StudentAgePalette.swift
// How long a child has waited, turned into a color.
//
// The thresholds and the three colors are the guide's settings, keyed by the
// list's vocabulary. Both lists read them once per list rather than once per
// row — five store lookups per chip or row was too much to spend on color, and
// the phone's dots were being drawn from the shipped defaults instead. One
// reader means the phone's dots and the Mac's bars agree.

import SwiftUI

/// The age thresholds and colors, resolved once for a whole list.
struct StudentAgePalette {
    let warningDays: Int
    let overdueDays: Int
    let fresh: Color
    let warning: Color
    let overdue: Color

    /// A child there is nothing to measure for is the most overdue thing on the
    /// list, not an unknown.
    func status(forDays days: Int?) -> LessonAgeStatus {
        guard let days else { return .overdue }
        if days >= max(0, overdueDays) { return .overdue }
        if days >= max(0, warningDays) { return .warning }
        return .fresh
    }

    func color(forDays days: Int?) -> Color {
        switch status(forDays: days) {
        case .fresh: fresh
        case .warning: warning
        case .overdue: overdue
        }
    }

    /// The grouped style's rule: color only for a child in the long-wait
    /// group, decided by the same test that puts them there, and nothing for
    /// anyone else. Shared by the rail and the phone's bar so they agree.
    func longWaitColor(forDays days: Int?) -> Color? {
        let band = WaitingStudentBands.band(forDays: days, longWaitThreshold: overdueDays)
        return band == .longWait ? overdue : nil
    }

    /// The metadata line stays secondary until the child is actually late, so
    /// the color means something when it arrives.
    func detailTint(forDays days: Int?) -> Color {
        switch status(forDays: days) {
        case .fresh: .secondary
        case .warning, .overdue: color(forDays: days)
        }
    }
}

/// One list's worth of age settings, read from the guide's preferences.
///
/// A `DynamicProperty` rather than a helper function so the five stored reads
/// live on the view that draws the list and update with it, exactly as they did
/// when each list declared them itself.
struct StudentAgePaletteReader: DynamicProperty {
    @SyncedAppStorage private var warningDays: Int
    @SyncedAppStorage private var overdueDays: Int
    @SyncedAppStorage private var freshColorHex: String
    @SyncedAppStorage private var warningColorHex: String
    @SyncedAppStorage private var overdueColorHex: String

    init(_ vocabulary: StudentWaitVocabulary) {
        let keys = vocabulary.ageKeys
        _warningDays = SyncedAppStorage(wrappedValue: LessonAgeDefaults.warningDays, keys.warningDays)
        _overdueDays = SyncedAppStorage(wrappedValue: LessonAgeDefaults.overdueDays, keys.overdueDays)
        _freshColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.freshColorHex, keys.freshColorHex)
        _warningColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.warningColorHex, keys.warningColorHex)
        _overdueColorHex = SyncedAppStorage(wrappedValue: LessonAgeDefaults.overdueColorHex, keys.overdueColorHex)
    }

    /// Resolve once for the whole list, not once per row.
    var palette: StudentAgePalette {
        StudentAgePalette(
            warningDays: warningDays,
            overdueDays: overdueDays,
            fresh: ColorUtils.color(from: freshColorHex),
            warning: ColorUtils.color(from: warningColorHex),
            overdue: ColorUtils.color(from: overdueColorHex)
        )
    }
}
