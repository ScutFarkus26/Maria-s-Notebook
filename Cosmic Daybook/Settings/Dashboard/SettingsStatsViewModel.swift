import Foundation
import CoreData
import SwiftUI

// MARK: - Notebook Records

/// The sections of Troubleshooting › Notebook at a glance.
enum NotebookRecordSection: String, CaseIterable, Identifiable {
    case teaching
    case planning
    case classroom
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teaching: return "Teaching"
        case .planning: return "Planning"
        case .classroom: return "Classroom"
        case .library: return "Library and templates"
        }
    }

    var systemImage: String {
        switch self {
        case .teaching: return "book.fill"
        case .planning: return "checklist"
        case .classroom: return "building.2.fill"
        case .library: return "archivebox.fill"
        }
    }

    var kinds: [NotebookRecordKind] {
        NotebookRecordKind.allCases.filter { $0.section == self }
    }
}

/// One kind of record the notebook holds, and the table rows it counts.
///
/// Every kind belongs to exactly one section and no two kinds count the same
/// rows, so the sections add up to the total. A presentation is one
/// `CDLessonAssignment` row, planned until it is given; the per-child record
/// of a lesson given is a `CDLessonPresentation`.
enum NotebookRecordKind: String, CaseIterable, Identifiable {
    // Teaching
    case students
    case lessons
    case presentationsPlanned
    case presentationsGiven
    case childPresentations
    case work
    case observations
    case meetings
    case practiceSessions
    // Planning
    case todos
    case reminders
    case tracks
    case trackEnrollments
    case calendarEvents
    case projects
    case goingOuts
    // Classroom
    case attendance
    case daysOff
    case supplies
    case supplyHistory
    case orders
    case issues
    case communityTopics
    case procedures
    // Library and templates
    case stories
    case albumMarks
    case documents
    case lessonFiles
    case communityFiles
    case noteTemplates
    case meetingTemplates
    case todoTemplates

    var id: String { rawValue }

    var section: NotebookRecordSection {
        switch self {
        case .students, .lessons, .presentationsPlanned, .presentationsGiven, .childPresentations,
             .work, .observations, .meetings, .practiceSessions:
            return .teaching
        case .todos, .reminders, .tracks, .trackEnrollments, .calendarEvents, .projects, .goingOuts:
            return .planning
        case .attendance, .daysOff, .supplies, .supplyHistory, .orders, .issues,
             .communityTopics, .procedures:
            return .classroom
        case .stories, .albumMarks, .documents, .lessonFiles, .communityFiles,
             .noteTemplates, .meetingTemplates, .todoTemplates:
            return .library
        }
    }

    var title: String {
        switch self {
        case .students: return "Students"
        case .lessons: return "Lessons"
        case .presentationsPlanned: return "Presentations planned"
        case .presentationsGiven: return "Presentations given"
        case .childPresentations: return "Per-child presentations"
        case .work: return "Work"
        case .observations: return "Observations"
        case .meetings: return "Meetings"
        case .practiceSessions: return "Practice sessions"
        case .todos: return "To-dos"
        case .reminders: return "Reminders"
        case .tracks: return "Tracks"
        case .trackEnrollments: return "Track enrollments"
        case .calendarEvents: return "Calendar events"
        case .projects: return "Projects"
        case .goingOuts: return "Going-outs"
        case .attendance: return "Attendance"
        case .daysOff: return "Days off"
        case .supplies: return "Staples"
        case .supplyHistory: return "Staple history"
        case .orders: return "Restock needs"
        case .issues: return "Issues"
        case .communityTopics: return "Community topics"
        case .procedures: return "Procedures"
        case .stories: return "Stories"
        case .albumMarks: return "Album marks"
        case .documents: return "Documents"
        case .lessonFiles: return "Lesson files"
        case .communityFiles: return "Community files"
        case .noteTemplates: return "Note templates"
        case .meetingTemplates: return "Meeting templates"
        case .todoTemplates: return "To-do templates"
        }
    }

    var systemImage: String {
        switch self {
        case .students: return "person.3.fill"
        case .lessons: return "text.book.closed.fill"
        case .presentationsPlanned: return "calendar.badge.clock"
        case .presentationsGiven: return "checkmark.circle.fill"
        case .childPresentations: return "person.crop.circle.badge.checkmark"
        case .work: return "doc.text.fill"
        case .observations: return "note.text"
        case .meetings: return "person.2.fill"
        case .practiceSessions: return "music.note.list"
        case .todos: return "checklist"
        case .reminders: return "bell.fill"
        case .tracks: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .trackEnrollments: return "person.line.dotted.person.fill"
        case .calendarEvents: return "calendar"
        case .projects: return "folder.fill"
        case .goingOuts: return "figure.walk"
        case .attendance: return "checkmark.square.fill"
        case .daysOff: return "calendar.badge.minus"
        case .supplies: return "shippingbox.fill"
        case .supplyHistory: return "clock.arrow.circlepath"
        case .orders: return "cart.fill"
        case .issues: return "exclamationmark.triangle.fill"
        case .communityTopics: return "bubble.left.and.bubble.right.fill"
        case .procedures: return "list.clipboard.fill"
        case .stories: return "books.vertical.fill"
        case .albumMarks: return "bookmark.fill"
        case .documents: return "doc.fill"
        case .lessonFiles: return "paperclip"
        case .communityFiles: return "paperclip.badge.ellipsis"
        case .noteTemplates: return "note.text.badge.plus"
        case .meetingTemplates: return "person.2.wave.2.fill"
        case .todoTemplates: return "checklist"
        }
    }

    /// A fixed line under the count, where the title alone could mislead.
    var caption: String? {
        switch self {
        case .presentationsPlanned: return "Not given yet"
        case .childPresentations: return "One for each child taught"
        case .supplyHistory: return "Stock changes"
        case .albumMarks: return "Bookmarks, notes, highlights"
        default: return nil
        }
    }

    /// The tables this kind counts. Album marks span three.
    var entities: [NSManagedObject.Type] {
        switch self {
        case .students: return [CDStudent.self]
        case .lessons: return [CDLesson.self]
        case .presentationsPlanned, .presentationsGiven: return [CDLessonAssignment.self]
        case .childPresentations: return [CDLessonPresentation.self]
        case .work: return [CDWorkModel.self]
        case .observations: return [CDNote.self]
        case .meetings: return [CDStudentMeeting.self]
        case .practiceSessions: return [CDPracticeSession.self]
        case .todos: return [CDTodoItemEntity.self]
        case .reminders: return [CDReminder.self]
        case .tracks: return [CDTrackEntity.self]
        case .trackEnrollments: return [CDStudentTrackEnrollmentEntity.self]
        case .calendarEvents: return [CDCalendarEvent.self]
        case .projects: return [CDProject.self]
        case .goingOuts: return [CDGoingOut.self]
        case .attendance: return [CDAttendanceRecord.self]
        case .daysOff: return [CDNonSchoolDay.self]
        case .supplies: return [CDSupply.self]
        case .supplyHistory: return [CDSupplyTransaction.self]
        case .orders: return [CDOrderItem.self]
        case .issues: return [CDIssue.self]
        case .communityTopics: return [CDCommunityTopicEntity.self]
        case .procedures: return [CDProcedure.self]
        case .stories: return [CDStory.self]
        case .albumMarks: return [CDAlbumBookmark.self, CDAlbumPageNote.self, CDAlbumHighlight.self]
        case .documents: return [CDDocument.self]
        case .lessonFiles: return [CDLessonAttachment.self]
        case .communityFiles: return [CDCommunityAttachmentEntity.self]
        case .noteTemplates: return [CDNoteTemplateEntity.self]
        case .meetingTemplates: return [CDMeetingTemplateEntity.self]
        case .todoTemplates: return [CDTodoTemplateEntity.self]
        }
    }

    /// Narrows the rows counted; planned and given split the presentations between them.
    fileprivate var predicate: NSPredicate? {
        switch self {
        case .presentationsPlanned: return NSPredicate(format: "presentedAt == nil")
        case .presentationsGiven: return NSPredicate(format: "presentedAt != nil")
        default: return nil
        }
    }
}

// MARK: - Stats View Model

/// Counts the records behind Settings: Notebook at a glance, and the template
/// counts the Overview and Templates panes show. Counts are asked of the store
/// (`count(for:)`), never fetched, so no rows are loaded.
///
/// Once loaded, the counts follow the notebook: a save on any context of the
/// same coordinator, or an import from iCloud, reloads them a moment after the
/// changes stop arriving, so a sync burst costs one reload.
@Observable @MainActor
final class SettingsStatsViewModel {
    private(set) var counts: [NotebookRecordKind: Int] = [:]
    private(set) var todoCompletedCount: Int = 0
    private(set) var issuesResolvedCount: Int = 0

    var noteTemplatesCount: Int { count(of: .noteTemplates) }
    var meetingTemplatesCount: Int { count(of: .meetingTemplates) }
    var todoTemplatesCount: Int { count(of: .todoTemplates) }

    func count(of kind: NotebookRecordKind) -> Int {
        counts[kind] ?? 0
    }

    func total(of section: NotebookRecordSection) -> Int {
        section.kinds.reduce(0) { $0 + count(of: $1) }
    }

    /// Every record the notebook holds: the sum of the sections, each row counted once.
    var totalRecordsCount: Int {
        NotebookRecordSection.allCases.reduce(0) { $0 + total(of: $1) }
    }

    /// The line under a count: how many are done or resolved, or what the count covers.
    func detail(for kind: NotebookRecordKind) -> String? {
        switch kind {
        case .todos: return "\(todoCompletedCount) done"
        case .issues: return "\(issuesResolvedCount) resolved"
        default: return kind.caption
        }
    }

    /// How long the counts wait after the last change before reloading.
    private let reloadDelay: Duration

    /// - Parameter reloadDelay: How long the counts wait after the last change; tests shorten it.
    init(reloadDelay: Duration = .seconds(1)) {
        self.reloadDelay = reloadDelay
    }

    /// Held while observing (and let go by `stopObserving()`), so a reload
    /// that comes due always has its context.
    @ObservationIgnored private var observedContext: NSManagedObjectContext?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    // `nonisolated(unsafe)` for the nonisolated `deinit`; written on the main actor only.
    @ObservationIgnored nonisolated(unsafe) private var changeObservers: [NSObjectProtocol] = []

    deinit {
        changeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Counts every kind of record now, and keeps the counts current until
    /// `stopObserving()`.
    func loadCounts(context: NSManagedObjectContext) {
        observeChanges(in: context)
        reload(from: context)
    }

    /// Stops following the notebook while Settings is off screen, so saves made
    /// elsewhere don't recount a pane nobody is looking at. `loadCounts` resumes.
    func stopObserving() {
        changeObservers.forEach(NotificationCenter.default.removeObserver)
        changeObservers = []
        observedContext = nil
        reloadTask?.cancel()
        reloadTask = nil
    }

    private func reload(from context: NSManagedObjectContext) {
        var loaded: [NotebookRecordKind: Int] = [:]
        for kind in NotebookRecordKind.allCases {
            loaded[kind] = kind.entities.reduce(0) { total, entity in
                total + Self.count(entity, matching: kind.predicate, in: context)
            }
        }
        counts = loaded
        todoCompletedCount = Self.count(
            CDTodoItemEntity.self, matching: NSPredicate(format: "isCompleted == YES"), in: context
        )
        issuesResolvedCount = Self.count(
            CDIssue.self, matching: NSPredicate(format: "resolvedAt != nil"), in: context
        )
    }

    /// Watches `context`'s coordinator (once per context): saves on any of its
    /// contexts, and imports from iCloud. A save elsewhere (Sample Class, TipKit)
    /// can't change these counts and is ignored on the posting thread.
    private func observeChanges(in context: NSManagedObjectContext) {
        guard observedContext !== context else { return }
        let center = NotificationCenter.default
        changeObservers.forEach(center.removeObserver)
        observedContext = context

        let coordinator = context.persistentStoreCoordinator
        let coordinatorID = coordinator.map(ObjectIdentifier.init)
        let changed: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        changeObservers = [
            center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { note in
                guard let saved = note.object as? NSManagedObjectContext,
                      saved.persistentStoreCoordinator.map(ObjectIdentifier.init) == coordinatorID else { return }
                changed()
            },
            center.addObserver(forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: nil) { _ in
                changed()
            }
        ]
    }

    /// Reloads once the changes have paused for `reloadDelay`.
    private func scheduleReload() {
        reloadTask?.cancel()
        let delay = reloadDelay
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let context = self.observedContext else { return }
            self.reload(from: context)
        }
    }

    /// Counts in the store: fetching every row just to count it would load the
    /// whole notebook (blob-bearing entities included) on the main actor.
    private static func count(
        _ entity: NSManagedObject.Type,
        matching predicate: NSPredicate?,
        in context: NSManagedObjectContext
    ) -> Int {
        // The name comes from this context's own model: `entity.entity()` is
        // ambiguous once a process has loaded more than one model (the test
        // host does), and a wrong name throws an Objective-C exception that
        // `try?` can't catch.
        guard let name = BackupFetchHelper.entityName(for: entity, in: context) else { return 0 }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
        request.predicate = predicate
        return (try? context.count(for: request)) ?? 0
    }
}
