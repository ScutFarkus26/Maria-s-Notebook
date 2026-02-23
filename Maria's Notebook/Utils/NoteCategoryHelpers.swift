//
//  NoteCategoryHelpers.swift
//  Maria's Notebook
//
//  Shared helpers for note category display
//

import SwiftUI

enum NoteCategoryHelpers {
    static func icon(for category: NoteCategory) -> String {
        switch category {
        case .academic: return "book.fill"
        case .behavioral: return "hand.raised.fill"
        case .social: return "person.2.fill"
        case .emotional: return "heart.fill"
        case .health: return "cross.fill"
        case .attendance: return "calendar"
        case .general: return "note.text"
        }
    }

    static func color(for category: NoteCategory) -> Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .green
        case .general: return .gray
        }
    }

    static func label(for category: NoteCategory) -> String {
        switch category {
        case .academic: return "Academic"
        case .behavioral: return "Behavioral"
        case .social: return "Social"
        case .emotional: return "Emotional"
        case .health: return "Health"
        case .attendance: return "Attendance"
        case .general: return "General"
        }
    }
}
