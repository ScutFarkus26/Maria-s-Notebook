// PieMenu.swift
// The quick-action set shared by the Today `+` menu, File > New and the command
// bar. The radial menu this was named for is gone; the five actions are not.

import SwiftUI

// MARK: - Pie Menu Action

enum PieMenuAction: String, CaseIterable, Hashable {
    case newPresentation
    case newWorkItem
    case recordPractice
    case newTodo
    case newNote

    var icon: String {
        switch self {
        case .newPresentation: return "person.crop.rectangle.stack"
        case .newWorkItem: return "tray.and.arrow.down"
        case .recordPractice: return "figure.run"
        case .newTodo: return "checklist.checked"
        case .newNote: return "square.and.pencil"
        }
    }

    var label: String {
        switch self {
        case .newPresentation: return "Present"
        case .newWorkItem: return "Work"
        case .recordPractice: return "Practice"
        case .newTodo: return "Todo"
        case .newNote: return "Note"
        }
    }

    var color: Color {
        switch self {
        case .newPresentation: return .blue
        case .newWorkItem: return .orange
        case .recordPractice: return .pink
        case .newTodo: return .green
        case .newNote: return .purple
        }
    }
}
