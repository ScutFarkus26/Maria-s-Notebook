// Handoff.swift
// What the app hands to the guide's other devices: the student, lesson or
// album page on screen, picked up from the Dock or the app switcher.

import Foundation
import SwiftUI

/// The three things Handoff carries between the guide's iPhone, iPad and Mac.
///
/// Apple's pattern for SwiftUI: a screen advertises an `NSUserActivity` with
/// `.userActivity(_:isActive:_:)` (or its `element:` form, which refreshes as
/// the value changes), and the receiving app answers with
/// `.onContinueUserActivity(_:perform:)`. Each activity type is declared in
/// both Info.plists under `NSUserActivityTypes`; Handoff only offers a type
/// the receiving app declares.
///
/// An activity carries record identifiers, never content: both devices
/// already hold the same records through CloudKit, and the album PDF through
/// the iCloud shelf or the guide's own folders. It is offered to the same
/// iCloud account only and kept out of search, Siri suggestions and public
/// indexing, since titles name children.
nonisolated enum Handoff {
    /// The activity types, as declared in `NSUserActivityTypes`.
    enum ActivityType {
        static let student = "DanielSDeBerry.MariasNoteBook.handoff.student"
        static let lesson = "DanielSDeBerry.MariasNoteBook.handoff.lesson"
        static let albumPage = "DanielSDeBerry.MariasNoteBook.handoff.albumPage"
    }

    /// `userInfo` keys.
    enum Key {
        static let id = "id"
        static let album = "album"
        static let page = "page"
    }

    /// Where a continued activity leads.
    enum Destination: Equatable {
        case student(UUID)
        case lesson(UUID)
        case albumPage(albumID: String, pageIndex: Int)
    }

    // MARK: Advertising

    static func describeStudent(_ activity: NSUserActivity, id: UUID, name: String) {
        configure(activity, title: name, userInfo: [Key.id: id.uuidString])
    }

    static func describeLesson(_ activity: NSUserActivity, id: UUID, name: String) {
        configure(activity, title: name, userInfo: [Key.id: id.uuidString])
    }

    static func describeAlbumPage(_ activity: NSUserActivity, albumID: String, title: String, pageIndex: Int) {
        configure(activity, title: "\(title), page \(pageIndex + 1)",
                  userInfo: [Key.album: albumID, Key.page: pageIndex])
    }

    private static func configure(_ activity: NSUserActivity, title: String, userInfo: [String: Any]) {
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        #if !os(macOS)
        activity.isEligibleForPrediction = false
        #endif
        activity.isEligibleForPublicIndexing = false
        activity.userInfo = userInfo
        activity.requiredUserInfoKeys = Set(userInfo.keys)
        activity.needsSave = true
    }

    // MARK: Continuing

    /// The destination an incoming activity names, or nil for a malformed one.
    static func destination(from activity: NSUserActivity) -> Destination? {
        let info = activity.userInfo ?? [:]
        switch activity.activityType {
        case ActivityType.student:
            return (info[Key.id] as? String).flatMap(UUID.init(uuidString:)).map(Destination.student)
        case ActivityType.lesson:
            return (info[Key.id] as? String).flatMap(UUID.init(uuidString:)).map(Destination.lesson)
        case ActivityType.albumPage:
            guard let album = info[Key.album] as? String, !album.isEmpty,
                  let page = info[Key.page] as? Int, page >= 0 else { return nil }
            return .albumPage(albumID: album, pageIndex: page)
        default:
            return nil
        }
    }
}

// MARK: - Receiving

/// Answers the three Handoff activities in a main window: in that window once
/// its screen is up, else through the router, which holds the request until
/// the screen that answers it appears (`WindowHandoff`).
private struct HandoffContinuationModifier: ViewModifier {
    let router: AppRouter
    /// This main window's own target, which its RootView hooks into.
    @State private var window = WindowHandoff()

    func body(content: Content) -> some View {
        content
            .environment(\.windowHandoff, window)
            .onContinueUserActivity(Handoff.ActivityType.student, perform: route)
            .onContinueUserActivity(Handoff.ActivityType.lesson, perform: route)
            .onContinueUserActivity(Handoff.ActivityType.albumPage, perform: route)
            // A main window already open takes the activity. With no window
            // saying so, SwiftUI opened another main window for every Handoff
            // (bug hunt 2026-10-17 #33).
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private func route(_ activity: NSUserActivity) {
        guard let destination = Handoff.destination(from: activity) else { return }
        window.continueHandoff(to: destination, router: router)
    }
}

extension View {
    /// Picks up a student, lesson or album page handed off from another device.
    func continuesHandoff(router: AppRouter) -> some View {
        modifier(HandoffContinuationModifier(router: router))
    }
}

/// The main window a Handoff arrived in, and its screen once that is up.
///
/// SwiftUI gives the activity to one main window. Sending it on through the
/// router, which every main window watches, let a window behind the one in
/// front switch section instead, whichever saw the change first (review c
/// #3). So once the window's RootView is up, the window takes the Handoff
/// itself (`QuickCaptureActions.continueHandoff`). Before then (a Handoff that
/// launches the app arrives while it says "Opening your notebook…"), the
/// router holds it until the screen that answers it appears.
final class WindowHandoff {
    /// This window's screen, while it's up.
    private weak var screen: QuickCaptureActions?

    func screenAppeared(_ actions: QuickCaptureActions) {
        screen = actions
    }

    /// Unhooks `actions` only while it is still this window's screen: the
    /// screen a classroom switch replaced can leave after the new one came.
    func screenDisappeared(_ actions: QuickCaptureActions) {
        if screen === actions { screen = nil }
    }

    func continueHandoff(to destination: Handoff.Destination, router: AppRouter) {
        if let screen {
            screen.continueHandoff(to: destination)
        } else {
            router.continueHandoff(to: destination)
        }
    }
}

extension EnvironmentValues {
    /// The enclosing main window's Handoff target, for its screen to take
    /// Handoffs in. Nil outside a main window (a detail window, a preview).
    @Entry var windowHandoff: WindowHandoff?
}
