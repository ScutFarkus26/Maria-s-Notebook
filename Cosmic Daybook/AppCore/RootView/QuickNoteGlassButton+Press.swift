// QuickNoteGlassButton+Press.swift
// How a press on the floating quick-capture button reads: a tap, a long press
// that opens the radial menu, or a drag that moves the button; and the radial
// menu's angles.

import CoreGraphics

enum QuickNoteButtonPress {
    /// How far a finger may drift and still be a long press.
    static let longPressSlop: CGFloat = 10

    static func distance(_ translation: CGSize) -> CGFloat {
        hypot(translation.width, translation.height)
    }

    /// Whether letting go with the finger at `translation` is a tap, which
    /// opens quick capture. `hasMoved` is whether this press dragged the button.
    /// Anything under the long-press slop is a tap: a finger drifts a point or
    /// two on its own, and that used to move the button instead (bug hunt
    /// 2026-10-17 #34).
    static func isTap(_ translation: CGSize, hasMoved: Bool) -> Bool {
        !hasMoved && distance(translation) < longPressSlop
    }

    /// Whether the long press may open the radial menu now. `translation` is
    /// the finger's, nil when no finger is down: a press the system cancelled
    /// opens nothing (bug hunt 2026-10-17 #38).
    static func opensMenu(translation: CGSize?, hasMoved: Bool) -> Bool {
        guard let translation else { return false }
        return isTap(translation, hasMoved: hasMoved)
    }
}

extension QuickNoteGlassButton {
    static func normalizedDegrees(_ angle: Double) -> Double {
        angle < 0 ? angle + 360 : angle
    }

    static func angleInRange(_ angle: Double, from start: Double, to end: Double) -> Bool {
        if start <= end {
            return angle >= start && angle < end
        }
        return angle >= start || angle < end
    }

    static func orbitOffset(for index: Int, radius: CGFloat) -> CGSize {
        let angle = Double(index) * (360.0 / 6.0)
        let radians = angle * .pi / 180
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}
