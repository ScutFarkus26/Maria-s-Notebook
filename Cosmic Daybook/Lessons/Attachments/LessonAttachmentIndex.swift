//
//  LessonAttachmentIndex.swift
//  Cosmic Daybook
//
//  Which lessons hold a file of their own, for the paperclip on the lesson
//  library's pills (plan "Lesson file attachments", Phase 3, Decision 8).
//

import CoreData
import Observation
import SwiftUI

/// The lessons that hold a lesson-scope attachment of their own, read with
/// one dictionary fetch and read again only after a save that touched a
/// `LessonAttachment`, never with a fetch per pill.
///
/// A sequence- or area-wide file doesn't count: it would badge every lesson
/// it reaches. Saves are watched on every context of this context's store
/// coordinator, so a file added on this device, by Claude over MCP or by a
/// CloudKit import is picked up. A burst of saves (an import) is one read.
@Observable
@MainActor
final class LessonAttachmentIndex {
    /// The object IDs of the lessons with a file of their own.
    private(set) var lessonIDs: Set<NSManagedObjectID> = []

    let context: NSManagedObjectContext
    private let center: NotificationCenter
    private let fetch: Fetch
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Set once in `init`, removed in `deinit`.
    @ObservationIgnored nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    typealias Fetch = @MainActor (NSManagedObjectContext) -> Set<NSManagedObjectID>

    /// - Parameter fetch: the read; tests wrap the real one to count calls.
    init(
        context: NSManagedObjectContext,
        center: NotificationCenter = .default,
        fetch: @escaping Fetch = LessonAttachmentIndex.fetchLessonIDs
    ) {
        self.context = context
        self.center = center
        self.fetch = fetch
        lessonIDs = fetch(context)
        let stores = Set((context.persistentStoreCoordinator?.persistentStores ?? []).map(ObjectIdentifier.init))
        observer = center.addObserver(
            forName: NSManagedObjectContext.didSaveObjectIDsNotification,
            object: nil,
            queue: nil,
            using: Self.saveHandler(stores: stores) { [weak self] in self?.scheduleRefresh() }
        )
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    /// Whether `lesson` holds a file of its own.
    func hasFile(_ lesson: CDLesson) -> Bool {
        lessonIDs.contains(lesson.objectID)
    }

    /// Reads the set again at the end of this main-actor turn, once however
    /// many saves asked for it.
    func scheduleRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.refreshTask = nil
            self.refresh()
        }
    }

    /// Reads the set now.
    func refresh() {
        let fresh = fetch(context)
        if fresh != lessonIDs { lessonIDs = fresh }
    }

    /// Waits for a refresh a save scheduled (tests).
    func settle() async {
        await refreshTask?.value
    }

    // MARK: - Reading

    /// The lessons with a lesson-scope attachment, in one dictionary fetch
    /// that registers no objects. A record whose scope is unreadable counts
    /// as lesson scope, as `CDLessonAttachment.scope` reads it.
    static func fetchLessonIDs(in context: NSManagedObjectContext) -> Set<NSManagedObjectID> {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["lesson"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(
            format: "lesson != nil AND NOT (scopeRaw IN %@)",
            [AttachmentScope.sequence.rawValue, AttachmentScope.area.rawValue]
        )
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap { $0["lesson"] as? NSManagedObjectID })
    }

    // MARK: - Watching saves

    nonisolated static let entityName = "LessonAttachment"

    /// The observer block: on the posting thread (any context's queue) it
    /// checks only object IDs, then hands a matching save to the main actor.
    /// Built here, outside the main-actor `init`, so it can't inherit
    /// main-actor isolation and trap when a background save posts
    /// (memory: background-save closure isolation crash, 2026-09-26).
    nonisolated private static func saveHandler(
        stores: Set<ObjectIdentifier>,
        onMain: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable (Notification) -> Void {
        { note in
            guard touchesAttachments(note.userInfo, stores: stores) else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { onMain() }
            } else {
                Task { @MainActor in onMain() }
            }
        }
    }

    /// True when a `didSaveObjectIDsNotification` payload inserted, updated
    /// or deleted a `LessonAttachment` in one of `stores`. Reads only object
    /// IDs, which are safe on any thread.
    nonisolated static func touchesAttachments(
        _ userInfo: [AnyHashable: Any]?, stores: Set<ObjectIdentifier>
    ) -> Bool {
        guard let userInfo else { return false }
        for key in [NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey, NSDeletedObjectIDsKey] {
            guard let ids = userInfo[key] as? Set<NSManagedObjectID> else { continue }
            for id in ids where id.entity.name == entityName {
                guard let store = id.persistentStore else { return true }
                if stores.contains(ObjectIdentifier(store)) { return true }
            }
        }
        return false
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The library's paperclip index; nil outside the library, where pills
    /// draw no paperclip.
    @Entry var lessonAttachmentIndex: LessonAttachmentIndex?
}

extension View {
    /// Gives the pills below one `LessonAttachmentIndex` over the
    /// environment's context, made again when that context changes (the
    /// Sample Class, a rebuilt store).
    func lessonAttachmentIndex() -> some View {
        modifier(LessonAttachmentIndexModifier())
    }
}

private struct LessonAttachmentIndexModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var context
    @State private var index: LessonAttachmentIndex?

    func body(content: Content) -> some View {
        content
            .environment(\.lessonAttachmentIndex, index?.context === context ? index : nil)
            .task(id: ObjectIdentifier(context)) {
                if index?.context !== context {
                    index = LessonAttachmentIndex(context: context)
                }
            }
    }
}

/// The paperclip a library pill carries when its lesson holds a file of its own.
struct LessonFileBadge: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "paperclip")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Has a file")
            .help("Has a file")
    }
}
