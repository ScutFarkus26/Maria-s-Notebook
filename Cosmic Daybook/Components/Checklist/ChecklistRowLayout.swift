//
//  ChecklistRowLayout.swift
//  Cosmic Daybook
//
//  Where each lesson row sits down the grid, below the pinned header: sequence bands,
//  section captions and lesson rows stacked in drawing order. A drag down a column
//  reads it to tell which row the pointer has reached, since bands and captions make
//  the rows anything but evenly spaced.
//

import CoreGraphics
import Foundation

struct ChecklistRowLayout: Equatable {
    /// One strip of the grid: a lesson row, or a band or caption (no lesson).
    struct Slot: Equatable {
        let lessonID: UUID?
        let height: CGFloat
    }

    private(set) var slots: [Slot] = []

    init(slots: [Slot] = []) {
        self.slots = slots
    }

    /// The lessons in drawing order.
    var lessonIDs: [UUID] { slots.compactMap(\.lessonID) }

    /// The top of `lessonID`'s row, nil when it isn't drawn.
    func top(of lessonID: UUID) -> CGFloat? {
        var y: CGFloat = 0
        for slot in slots {
            if slot.lessonID == lessonID { return y }
            y += slot.height
        }
        return nil
    }

    /// The lesson row at `y`. Over a band or caption, the nearest row on the side the
    /// pointer came from (`towardTop`: the row above it); past either end, the end row.
    func lesson(atY y: CGFloat, towardTop: Bool) -> UUID? {
        let lessons = lessonIDs
        guard let first = lessons.first, let last = lessons.last else { return nil }
        if y < 0 { return first }
        var top: CGFloat = 0
        var previous: UUID?
        for (index, slot) in slots.enumerated() {
            let bottom = top + slot.height
            if y < bottom {
                if let lessonID = slot.lessonID { return lessonID }
                if towardTop, let previous { return previous }
                return slots[(index + 1)...].lazy.compactMap(\.lessonID).first ?? previous
            }
            if let lessonID = slot.lessonID { previous = lessonID }
            top = bottom
        }
        return last
    }
}
