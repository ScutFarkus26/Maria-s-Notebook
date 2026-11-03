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

    var showsPresentations: Bool { self != .work }
    var showsWork: Bool { self != .presentations }

    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let value = Self(rawValue: rawValue) else { return .everything }
        return value
    }
}
