//
//  ChecklistKeyCommand.swift
//  Cosmic Daybook
//
//  The checklist's plain keys, read only while the grid has focus (a hardware
//  keyboard on the Mac or iPad): arrows move the cursor, Return or Space opens the
//  card, P presented, M mastered, I the Inbox, Delete clears, Escape backs out.
//  No ⌘ shortcuts and no menu commands; a key with ⌘, ⌃ or ⌥ held is left alone.
//

import SwiftUI

enum ChecklistKeyCommand: Equatable {
    case move(dx: Int, dy: Int)
    case openCard
    case presented
    case mastered
    case toggleInbox
    case clear
    case dismiss

    /// The command for one key press, or nil to let it through.
    static func command(key: KeyEquivalent, characters: String, modifiers: EventModifiers) -> ChecklistKeyCommand? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        if let command = byKey.first(where: { $0.key == key })?.command { return command }
        return byLetter[characters.lowercased()]
    }

    private static let byKey: [(key: KeyEquivalent, command: ChecklistKeyCommand)] = [
        (.leftArrow, .move(dx: -1, dy: 0)),
        (.rightArrow, .move(dx: 1, dy: 0)),
        (.upArrow, .move(dx: 0, dy: -1)),
        (.downArrow, .move(dx: 0, dy: 1)),
        (.return, .openCard),
        (.space, .openCard),
        (.delete, .clear),
        (.deleteForward, .clear),
        (.escape, .dismiss)
    ]

    private static let byLetter: [String: ChecklistKeyCommand] = [
        "p": .presented,
        "m": .mastered,
        "i": .toggleInbox
    ]

    /// The cell action a key runs on the cursor's cell; nil for moving, opening and dismissing.
    var cellAction: ChecklistCellAction? {
        switch self {
        case .presented: return .markPresented
        case .mastered: return .markComplete
        case .toggleInbox: return .toggleScheduled
        case .clear: return .clearStatus
        case .move, .openCard, .dismiss: return nil
        }
    }
}
