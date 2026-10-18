// ClassroomSwitchQuestion.swift
// "Switch classroom?", asked over whatever is in front.
//
// A switch rebuilds every main window and closes the detail windows that
// hold typing, so while something is open it asks first (bug hunt 2026-10-17
// #31, D2). The question is most often wanted while a sheet is up in the very
// window it was asked from — the Classroom menu over File › New Note… — where
// a SwiftUI dialog on the window's root can't show: AppKit held it until the
// sheet closed, and UIKit refused it and left it pending (review c #1). So
// the question is put up over the sheet in front instead.

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ClassroomSwitchQuestion {
    static let title = "Switch classroom?"
    static let message = "What you’re typing in open windows will be lost."
    static let switchTitle = "Switch"
    static let cancelTitle = "Cancel"

    #if os(macOS)
    /// The question on screen, so asking again doesn't stack a second one.
    private static weak var showing: NSAlert?

    /// Asks in the key window (the one the switch was chosen in, or its
    /// sheet); `onSwitch` runs on Switch, and Cancel changes nothing. False
    /// when no window is open to ask in.
    @discardableResult
    static func ask(onSwitch: @escaping () -> Void) -> Bool {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return false }
        return ask(in: window, onSwitch: onSwitch)
    }

    /// Asks over the sheet in front of `window`, or on the window itself.
    @discardableResult
    static func ask(in window: NSWindow, onSwitch: @escaping () -> Void) -> Bool {
        if let showing, showing.window.isVisible { return true }
        var front = window
        while let sheet = front.attachedSheet {
            front = sheet
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: switchTitle).hasDestructiveAction = true
        alert.addButton(withTitle: cancelTitle)
        showing = alert
        alert.beginSheetModal(for: front) { response in
            // Anything but Switch, a sheet closed under it included, is a Cancel.
            if response == .alertFirstButtonReturn { onSwitch() }
        }
        return true
    }
    #else
    /// The question on screen, so asking again doesn't stack a second one.
    private static weak var showing: UIAlertController?

    /// Asks in the key window of the active scene (the one the switch was
    /// chosen in); `onSwitch` runs on Switch, and Cancel changes nothing.
    /// False when no window is open to ask in.
    @discardableResult
    static func ask(onSwitch: @escaping () -> Void) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return false }
        return ask(in: window, onSwitch: onSwitch)
    }

    /// Asks over the screen in front in `window`.
    @discardableResult
    static func ask(in window: UIWindow, animated: Bool = true, onSwitch: @escaping () -> Void) -> Bool {
        if let showing, showing.presentingViewController != nil, !showing.isBeingDismissed { return true }
        guard let front = frontmostPresenter(in: window) else { return false }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: switchTitle, style: .destructive) { _ in onSwitch() })
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        showing = alert
        if let transition = front.transitionCoordinator {
            // A sheet still coming up, or one on its way out: UIKit refuses a
            // presentation mid-transition, so ask once it has settled.
            transition.animate(alongsideTransition: nil) { _ in
                front.present(alert, animated: animated)
            }
        } else {
            front.present(alert, animated: animated)
        }
        return true
    }

    /// The screen in front in `window`: its root, or the sheet, popover or
    /// alert on top of it, passing over one already closing (review c #10).
    static func frontmostPresenter(in window: UIWindow) -> UIViewController? {
        guard var front = window.rootViewController else { return nil }
        while let presented = front.presentedViewController, !presented.isBeingDismissed {
            front = presented
        }
        return front
    }
    #endif
}
