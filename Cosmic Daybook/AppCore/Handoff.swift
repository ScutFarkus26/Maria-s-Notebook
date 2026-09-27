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

/// Answers the three Handoff activities in a main window by routing to the
/// same place the app's own "open" requests go.
private struct HandoffContinuationModifier: ViewModifier {
    let router: AppRouter

    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(Handoff.ActivityType.student, perform: route)
            .onContinueUserActivity(Handoff.ActivityType.lesson, perform: route)
            .onContinueUserActivity(Handoff.ActivityType.albumPage, perform: route)
    }

    private func route(_ activity: NSUserActivity) {
        guard let destination = Handoff.destination(from: activity) else { return }
        router.continueHandoff(to: destination)
    }
}

extension View {
    /// Picks up a student, lesson or album page handed off from another device.
    func continuesHandoff(router: AppRouter) -> some View {
        modifier(HandoffContinuationModifier(router: router))
    }
}
