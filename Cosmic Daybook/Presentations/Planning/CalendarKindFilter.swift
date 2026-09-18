// CalendarKindFilter.swift
// What the merged Lessons & Work calendar is currently showing.
//
// Replaces two independent checkboxes that used to live on two separate
// calendars — a "Presentations" box on the work one and a "Work" box on the
// presentations one, in two settings keys that could disagree.

import Foundation
import SwiftUI

enum CalendarKindFilter: String, CaseIterable, Identifiable, Sendable {
    case everything
    case presentations
    case work

    var id: Self { self }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .presentations: "Presentations"
        case .work: "Work"
        }
    }

    var systemImage: String {
        switch self {
        case .everything: "square.stack"
        case .presentations: "person.chalkboard"
        case .work: "tray.full"
        }
    }

    var showsPresentations: Bool { self != .work }
    var showsWork: Bool { self != .presentations }

    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let value = Self(rawValue: rawValue) else { return .everything }
        return value
    }

    /// Carries a guide's old per-calendar checkboxes over the first time the
    /// merged calendar opens. Hiding one kind on either former calendar meant
    /// "show me the other one", so that becomes the single-kind selection;
    /// anything else — including the contradictory both-hidden state — starts
    /// at Everything.
    static func migratedFromLegacyToggles(in defaults: UserDefaults = .standard) -> Self {
        if let existing = defaults.string(forKey: UserDefaultsKeys.calendarVisibleKinds) {
            return resolved(rawValue: existing)
        }

        // `object(forKey:)` distinguishes "never set" from "set to false"; both
        // legacy keys defaulted to true.
        let showedPresentations = defaults.object(
            forKey: UserDefaultsKeys.workCalendarShowPresentations
        ) as? Bool ?? true
        let showedWork = defaults.object(
            forKey: UserDefaultsKeys.presentationsCalendarShowWork
        ) as? Bool ?? true

        let migrated: Self
        switch (showedPresentations, showedWork) {
        case (false, true): migrated = .work
        case (true, false): migrated = .presentations
        default: migrated = .everything
        }

        defaults.set(migrated.rawValue, forKey: UserDefaultsKeys.calendarVisibleKinds)
        return migrated
    }
}
