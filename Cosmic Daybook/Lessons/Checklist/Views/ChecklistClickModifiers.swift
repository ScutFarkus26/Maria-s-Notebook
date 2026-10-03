//
//  ChecklistClickModifiers.swift
//  Cosmic Daybook
//
//  Which modifier keys are held as a checklist cell is clicked: ⌘ toggles the cell
//  in the selection, Shift extends it. SwiftUI's tap gesture doesn't say, so the
//  Mac asks AppKit for the keys held now and an iPad asks its hardware keyboard
//  (GameController); with no keyboard attached every click is a plain one.
//

#if os(macOS)
import AppKit
#else
import GameController
#endif

enum ChecklistClickModifiers {

    /// The kind of click the keys held right now make.
    static var current: ClassAreaChecklistViewModel.ClickKind {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .toggle }
        if flags.contains(.shift) { return .extend }
        return .plain
        #else
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return .plain }
        func isHeld(_ codes: GCKeyCode...) -> Bool {
            codes.contains { keyboard.button(forKeyCode: $0)?.isPressed == true }
        }
        if isHeld(.leftGUI, .rightGUI) { return .toggle }
        if isHeld(.leftShift, .rightShift) { return .extend }
        return .plain
        #endif
    }
}
