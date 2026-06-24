import CoreData
import CloudKit
import OSLog

/// Manages the Core Data stack with NSPersistentCloudKitContainer.
///
/// Two stores route entities to separate CloudKit databases:
/// - **Private store** (`private.sqlite`) — teacher-level data (notes, work, attendance, todos, etc.)
/// - **Shared store** (`shared.sqlite`) — classroom-level data (students, lessons, tracks, procedures, etc.)
///
/// NSPersistentCloudKitContainer handles sync, offline queuing, and conflict resolution automatically.
@MainActor
final class CoreDataStack {
    nonisolated private static let logger = Logger.app(category: "CoreDataStack")

    // MARK: - Active Model

    /// The managed object model used by the current stack.
    /// Used by `CDFetchRequest` to resolve entity names safely in multi-store configurations,
    /// avoiding the "Multiple NSEntityDescriptions" ambiguity with `NSManagedObject.entity()`.
    ///
    /// Lock-guarded: `CDFetchRequest` reads this off the main actor while stack
    /// initializations write it, so all access goes through `activeModelLock` to
    /// avoid an unsynchronized data race on the mutable static.
    nonisolated static var activeModel: NSManagedObjectModel? {
        activeModelLock.lock()
        defer { activeModelLock.unlock() }
        return _activeModel
    }
    nonisolated(unsafe) private static var _activeModel: NSManagedObjectModel?
    nonisolated private static let activeModelLock = NSLock()

    nonisolated private static func setActiveModel(_ model: NSManagedObjectModel?) {
        activeModelLock.lock()
        defer { activeModelLock.unlock() }
        _activeModel = model
    }

    // MARK: - Container

    let container: NSPersistentCloudKitContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Whether CloudKit sync is active (vs local-only fallback).
    private(set) var isCloudKitActive: Bool = false

    /// Persistent history processor for serialized remote change handling.
    private(set) var historyProcessor: PersistentHistoryProcessor?

    /// Token for the remote change notification observer.
    /// `nonisolated(unsafe)` so the (nonisolated) `deinit` can read it to remove
    /// the observer — it is written once during init and read once at deinit, with
    /// no concurrent access, so the unchecked annotation is safe here.
    nonisolated(unsafe) private var remoteChangeObserver: (any NSObjectProtocol)?

    // MARK: - Store Configurations

    /// Configuration name for the private (per-teacher) store.
    nonisolated static let privateConfiguration = "Private"
    /// Configuration name for the shared (classroom) store.
    nonisolated static let sharedConfiguration = "Shared"

    // MARK: - Entity Routing

    /// Entities stored in the shared (classroom) store.
    /// These are owned by the lead guide and shared via CKShare with assistants.
    nonisolated static let sharedEntityNames: Set<String> = [
        "Student",
        "Lesson",
        "LessonAttachment",
        "LessonPresentation",
        "Track",
        "TrackStep",
        "SequenceTrack",
        "StudentTrackEnrollment",
        "Procedure",
        "Supply",
        "SupplyTransaction",
        "Schedule",
        "ScheduleSlot",
        "CommunityTopic",
        "ProposedSolution",
        "CommunityAttachment",
        "ClassroomJob",
        "JobAssignment",
        "NoteTemplate",
        "MeetingTemplate",
        "TodoTemplate",
        "Resource",
        "NonSchoolDay",
        "SchoolDayOverride",
        "GoingOut",
        "GoingOutChecklistItem",
        "CalendarNote",
        "SampleWork",
        "SampleWorkStep",
        "ClassroomMembership",
        "Story",
        "BookClubPacket"
    ]

    /// Entities stored in the private (per-teacher) store.
    /// Each teacher has their own copy of these records.
    nonisolated static let privateEntityNames: Set<String> = [
        "Note",
        "NoteStudentLink",
        "WorkModel",
        "WorkStep",
        "WorkCheckIn",
        "WorkParticipantEntity",
        "WorkCompletionRecord",
        "PracticeSession",
        "AttendanceRecord",
        "LessonAssignment",
        "StudentMeeting",
        "ScheduledMeeting",
        "Project",
        "ProjectSession",
        "ProjectAssignmentTemplate",
        "ProjectRole",
        "ProjectTemplateWeek",
        "ProjectWeekRoleAssignment",
        "Reminder",
        "CalendarEvent",
        "TodoItem",
        "TodoSubtask",
        "TodayAgendaOrder",
        "Issue",
        "IssueAction",
        "DevelopmentSnapshot",
        "PlanningRecommendation",
        "Document",
        "YearPlanEntry",
        "LessonSequenceSettings",
        "ParentCommunication",
        "MeetingWorkReview",
        "StudentFocusItem",
        "DayPad",
        "BookClubSession",
        "BookClubMeeting",
        "LessonRecallCheck"
    ]

    // MARK: - Store URLs

    /// Directory for Core Data store files.
    nonisolated static func storeDirectory() -> URL {
        let fm = FileManager.default
        let appSupport: URL
        do {
            appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            logger.warning("Failed to get application support directory: \(error)")
            return fm.temporaryDirectory
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "MariasNotebook"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create store directory: \(error)")
        }
        return dir
    }

    nonisolated static func privateStoreURL() -> URL {
        storeDirectory().appendingPathComponent("private.sqlite")
    }

    nonisolated static func sharedStoreURL() -> URL {
        storeDirectory().appendingPathComponent("shared.sqlite")
    }

    /// Unified store URL for local-only mode (single store, all entities).
    nonisolated static func unifiedStoreURL() -> URL {
        storeDirectory().appendingPathComponent("unified.sqlite")
    }

    // MARK: - Initialization

    /// Creates the Core Data stack.
    ///
    /// - Parameters:
    ///   - enableCloudKit: Whether to enable CloudKit sync. Defaults to the user's preference.
    ///   - inMemory: If true, uses in-memory stores (for testing/fallback).
    ///   - preserveSplitStoreLayout: If true while CloudKit is disabled, keeps using
    ///     the existing private/shared store files instead of switching to the unified
    ///     local-only store. This lets the app continue using the last cached data set
    ///     when CloudKit initialization fails at launch.
    init(
        enableCloudKit: Bool = true,
        inMemory: Bool = false,
        preserveSplitStoreLayout: Bool = false
    ) throws {
        let start = Date()
        Self.logger.info("Initializing CoreDataStack (CloudKit: \(enableCloudKit), inMemory: \(inMemory))...")

        // Honor a deferred "Reset Local Cache" request from Settings →
        // Database. We delete the on-disk stores BEFORE the container is
        // created so the next loadPersistentStores reconstitutes from
        // CloudKit. Migration / sharing completion flags are also cleared so
        // post-launch bootstrap re-runs against the fresh data.
        if !inMemory, UserDefaults.standard.bool(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch) {
            let defaults = UserDefaults.standard
            let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
            let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
            let resetMsg = "Consuming pending local cache reset before store load. " +
                "source=\(source), armedAt=\(armedAt)"
            Self.logger.warning("\(resetMsg, privacy: .public)")
            Self.performLocalCacheReset()
        }

        let modelName = "MariasNotebook"
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let cachedModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw CoreDataStackError.modelNotFound(modelName)
        }
        // Copy the model so mutations (like assignEntitiesToConfigurations) don't
        // pollute the cached instance. NSManagedObjectModel(contentsOf:) can return
        // a cached object, and calling setEntities on it would affect subsequent inits.
        let model = cachedModel.copy() as! NSManagedObjectModel  // swiftlint:disable:this force_cast
        Self.setActiveModel(model)

        // Validate that all entities in our routing tables exist in the model
        Self.validateEntityRouting(model: model)

        // Assign entities to configurations BEFORE creating the container.
        // NSPersistentCloudKitContainer's init creates an NSPersistentStoreCoordinator,
        // which makes the model immutable — so all setEntities calls must happen first.
        if (enableCloudKit || preserveSplitStoreLayout) && !inMemory {
            Self.assignEntitiesToConfigurations(model: model)
        }

        container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)

        if enableCloudKit && !inMemory {
            // CloudKit mode: two stores (private + shared) for separate CloudKit databases.

            let privateDesc = Self.makeStoreDescription(
                url: Self.privateStoreURL(),
                configuration: Self.privateConfiguration
            )
            let sharedDesc = Self.makeStoreDescription(
                url: Self.sharedStoreURL(),
                configuration: Self.sharedConfiguration
            )

            Self.enableHistoryTracking(privateDesc)
            Self.enableHistoryTracking(sharedDesc)
            Self.configureCloudKit(privateDescription: privateDesc, sharedDescription: sharedDesc)
            isCloudKitActive = true

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        } else if preserveSplitStoreLayout && !inMemory {
            // Degraded local-cached mode: keep using the existing private/shared store
            // files without CloudKit mirroring so the user can open the last known local
            // cache immediately when CloudKit startup is unhealthy.
            let privateDesc = Self.makeStoreDescription(
                url: Self.privateStoreURL(),
                configuration: Self.privateConfiguration
            )
            let sharedDesc = Self.makeStoreDescription(
                url: Self.sharedStoreURL(),
                configuration: Self.sharedConfiguration
            )

            Self.enableHistoryTracking(privateDesc)
            Self.enableHistoryTracking(sharedDesc)

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        } else {
            // Local-only mode: single unified store with ALL entities.
            // This avoids the "Multiple NSEntityDescriptions" problem that occurs when
            // entities are split across two configurations — Core Data's +entity lookup
            // can't disambiguate, causing @FetchRequest crashes.
            let desc: NSPersistentStoreDescription
            if inMemory {
                let url = URL(fileURLWithPath: "/dev/null/unified")
                desc = NSPersistentStoreDescription(url: url)
                desc.type = NSInMemoryStoreType
            } else {
                desc = Self.makeStoreDescription(
                    url: Self.unifiedStoreURL(),
                    configuration: nil
                )
            }
            Self.enableHistoryTracking(desc)

            container.persistentStoreDescriptions = [desc]
        }

        // Pre-clean orphan entity rows from on-disk stores. When entities are dropped
        // from the model, CloudKit's ANSCKRECORDMETADATA table retains rows pointing at
        // their old Z_ENT IDs, which makes lightweight migration fail with a UNIQUE
        // constraint violation. Stripping those rows first lets migration succeed.
        if !inMemory {
            for desc in container.persistentStoreDescriptions {
                guard let url = desc.url, desc.type == NSSQLiteStoreType else { continue }
                Self.cleanOrphanEntityMetadata(storeURL: url, model: model)
            }
        }

        // Load stores synchronously
        var loadErrors: [Error] = []
        container.loadPersistentStores { description, error in
            if let error {
                Self.logger.error("Failed to load store '\(description.configuration ?? "default")': \(error)")
                loadErrors.append(error)
            } else {
                Self.logger.info("Loaded store: \(description.configuration ?? "default")")
            }
        }

        if !loadErrors.isEmpty {
            // If CloudKit stores failed, try local-only fallback
            if enableCloudKit && !inMemory {
                Self.logger.warning("CloudKit store load failed, retrying without CloudKit...")
                isCloudKitActive = false
                throw CoreDataStackError.cloudKitLoadFailed(loadErrors.first!)
            }
            throw CoreDataStackError.storeLoadFailed(loadErrors.first!)
        }

        // Configure view context
        configureViewContext()

        // Create persistent history processor
        historyProcessor = PersistentHistoryProcessor(container: container)

        // Listen for remote changes (must dispatch to main queue since this class is @MainActor
        // but NSPersistentStoreRemoteChange fires on a background queue)
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Compute the school-day relevance flag here (queue: .main) so we don't
            // need to send the non-Sendable Notification across the actor boundary.
            let relevantNames: Set<String> = ["NonSchoolDay", "SchoolDayOverride"]
            let changedIDs = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
                .compactMap { notification.userInfo?[$0] as? Set<NSManagedObjectID> }
                .flatMap { $0 }
            let shouldInvalidateSchoolDayCache: Bool = changedIDs.isEmpty
                || changedIDs.contains { relevantNames.contains($0.entity.name ?? "") }
            Task { @MainActor in
                self.handleRemoteChangeNotification(invalidateSchoolDayCache: shouldInvalidateSchoolDayCache)
            }
        }

        let elapsed = String(format: "%.3f", Date().timeIntervalSince(start))
        Self.logger.info("CoreDataStack initialized in \(elapsed)s")
    }

    deinit {
        // The production stack lives for the whole process, but launch-time
        // fallbacks and tests create throwaway stacks; without this they leak a
        // main-queue observer that keeps firing remote-change handlers on a dead
        // stack. Reading `remoteChangeObserver` here is safe (see its declaration).
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    // MARK: - View Context Configuration

    private func configureViewContext() {
        let ctx = container.viewContext
        // Automatically merge remote changes into the view context
        ctx.automaticallyMergesChangesFromParent = true
        // Last-writer-wins: remote property values override local on conflict
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // Tag transactions so the history processor can filter out our own writes
        ctx.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        // Disable autosave — we use explicit saves via SaveCoordinator
        // (Mirrors the existing SwiftData behavior where autosave was disabled)
    }

    // MARK: - Empty Fallback

    /// Builds a minimal, always-constructible stack from an empty in-code model and
    /// an in-memory store. Used only as an absolute last resort when even the normal
    /// in-memory fallback can't be created (e.g. the compiled `.momd` is missing or
    /// corrupt), so the app can still launch into the database-error UI instead of
    /// crashing. Has no entities — callers must already be in an error state.
    static func makeEmptyFallback() -> CoreDataStack {
        CoreDataStack(emptyFallback: ())
    }

    private init(emptyFallback: Void) {
        let model = NSManagedObjectModel()
        Self.setActiveModel(model)
        let fallbackContainer = NSPersistentCloudKitContainer(
            name: "MariasNotebookFallback",
            managedObjectModel: model
        )
        let desc = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null/fallback"))
        desc.type = NSInMemoryStoreType
        fallbackContainer.persistentStoreDescriptions = [desc]
        fallbackContainer.loadPersistentStores { _, _ in }
        container = fallbackContainer
        isCloudKitActive = false
        configureViewContext()
    }

    // MARK: - Background Context

    /// Creates a new background context for batch operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        ctx.transactionAuthor = PersistentHistoryProcessor.transactionAuthor
        return ctx
    }

    // MARK: - Store Accessors

    /// The NSPersistentStore for the shared (classroom-level) configuration.
    var sharedPersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == Self.sharedConfiguration
        }
    }

    /// The NSPersistentStore for the private (per-teacher) configuration.
    var privatePersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            store.configurationName == Self.privateConfiguration
        }
    }

    // MARK: - Remote Change Handling

    private func handleRemoteChangeNotification(invalidateSchoolDayCache: Bool) {
        // Only invalidate school-day caches when NonSchoolDay or SchoolDayOverride
        // entities actually changed (computed by the caller before the actor hop).
        // Fail-open: if the notification carried no object-ID info the caller passes true.
        if invalidateSchoolDayCache {
            NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
        }
        guard let processor = historyProcessor else { return }
        Task {
            await processor.processRemoteChanges()
        }
    }

    // MARK: - Store Description Builders

    private static func makeStoreDescription(
        url: URL,
        configuration: String?
    ) -> NSPersistentStoreDescription {
        let desc = NSPersistentStoreDescription(url: url)
        if let configuration {
            desc.configuration = configuration
        }
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        return desc
    }

    private static func enableHistoryTracking(_ description: NSPersistentStoreDescription) {
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    // MARK: - CloudKit Configuration

    private static func configureCloudKit(
        privateDescription: NSPersistentStoreDescription,
        sharedDescription: NSPersistentStoreDescription
    ) {
        guard let containerID = CloudKitConfigurationService.getContainerID() else {
            logger.warning("No CloudKit container ID found, skipping CloudKit configuration")
            return
        }

        // Private store → private CloudKit database
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        // Shared store → shared CloudKit database
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        logger.info("CloudKit configured: container=\(containerID)")
    }

    // MARK: - Entity Routing

    /// Assigns entities to Private/Shared configurations in the managed object model.
    ///
    /// Canonical NSPersistentCloudKitContainer sharing pattern: classroom-level
    /// entities (Students, Lessons, Tracks, …) live in BOTH configurations so
    /// they can be routed to either store at runtime.
    ///
    /// - On the **lead-guide** device, new classroom records go to the
    ///   `.private`-scope private store (private.sqlite) — Core Data routes new
    ///   inserts to the first store that contains the entity, and we order
    ///   `persistentStoreDescriptions` as `[privateDesc, sharedDesc]`. The
    ///   lead-guide-owned classroom data must live in `.private` scope for
    ///   `container.share(_:to:)` to succeed; `.shared` scope is reserved for
    ///   data the user has accepted *from other users*.
    /// - On the **assistant** device, accepted classroom shares land in the
    ///   `.shared`-scope shared store (shared.sqlite) via
    ///   `container.acceptShareInvitations(into:)`. The same entity types are
    ///   available there too.
    ///
    /// Teacher-private entities (Notes, Work, Attendance, etc.) remain
    /// exclusive to the Private configuration.
    private static func assignEntitiesToConfigurations(model: NSManagedObjectModel) {
        let allEntities = model.entities

        let sharedEntities = allEntities.filter { sharedEntityNames.contains($0.name ?? "") }
        let privateOnlyEntities = allEntities.filter { privateEntityNames.contains($0.name ?? "") }

        // Shared configuration: classroom entities only (receive-shares side).
        model.setEntities(sharedEntities, forConfigurationName: sharedConfiguration)

        // Private configuration: teacher-private + classroom entities. Classroom
        // entities appearing in both configs is what enables the canonical
        // two-store sharing pattern.
        let privateConfigEntities = privateOnlyEntities + sharedEntities
        model.setEntities(privateConfigEntities, forConfigurationName: privateConfiguration)

        let classroomCount = sharedEntities.count
        let privateExclusiveCount = privateOnlyEntities.count
        let privateConfigCount = privateConfigEntities.count
        let routingMsg = "Entity routing: \(privateConfigCount) in private " +
            "(\(privateExclusiveCount) exclusive + \(classroomCount) classroom), " +
            "\(classroomCount) in shared"
        logger.info("\(routingMsg, privacy: .public)")
    }

    /// Validates that all entity names in our routing tables exist in the model.
    /// Logs warnings for mismatches but does not crash — allows the app to continue.
    private static func validateEntityRouting(model: NSManagedObjectModel) {
        let modelEntityNames = Set(model.entities.compactMap(\.name))
        let routedNames = sharedEntityNames.union(privateEntityNames)

        let missingFromModel = routedNames.subtracting(modelEntityNames)
        if !missingFromModel.isEmpty {
            logger.warning("Entity routing references entities not in model: \(missingFromModel)")
        }

        let unrouted = modelEntityNames.subtracting(routedNames)
        if !unrouted.isEmpty {
            logger.warning("Model entities not assigned to any store: \(unrouted)")
        }
    }

    // MARK: - Store Reset

    /// Deletes both Core Data store files and their WAL/SHM companions.
    nonisolated static func resetStores() throws {
        let fm = FileManager.default
        for url in [privateStoreURL(), sharedStoreURL(), unifiedStoreURL()] {
            guard fm.fileExists(atPath: url.path) else { continue }
            try fm.removeItem(at: url)
            // Also remove WAL and SHM files
            let walURL = url.appendingPathExtension("wal")
            let shmURL = url.appendingPathExtension("shm")
            if fm.fileExists(atPath: walURL.path) { try fm.removeItem(at: walURL) }
            if fm.fileExists(atPath: shmURL.path) { try fm.removeItem(at: shmURL) }
        }
        logger.info("Core Data stores reset")
    }

    /// Performs the "Reset Local Cache" sequence at launch:
    ///   1. Delete the on-disk persistent stores (so the container will
    ///      reconstitute from CloudKit on load).
    ///   2. Clear migration/sharing completion flags so the post-launch
    ///      bootstrap re-runs against the fresh data set.
    ///   3. Clear the request flag so we only do this once per request.
    ///
    /// Caller must verify `resetLocalCacheOnLaunch` is true before invoking.
    /// Any errors are logged but not thrown — partial cleanup is still better
    /// than aborting launch with no fallback.
    private static func performLocalCacheReset() {
        let defaults = UserDefaults.standard
        let armedAt = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedAt) ?? "unknown"
        let source = defaults.string(forKey: UserDefaultsKeys.resetLocalCacheArmedSource) ?? "unknown"
        let cacheResetMsg = "Reset Local Cache requested — deleting on-disk stores " +
            "and clearing migration flags. source=\(source), armedAt=\(armedAt)"
        logger.warning("\(cacheResetMsg, privacy: .public)")
        do {
            try resetStores()
        } catch {
            logger.error("Reset Local Cache: failed to delete stores — \(error.localizedDescription)")
        }
        // Re-run one-shot migrations / share auto-create against the fresh
        // data so the post-refactor state is consistent.
        defaults.removeObject(forKey: UserDefaultsKeys.classroomStoreMigrationV1Complete)
        defaults.removeObject(forKey: UserDefaultsKeys.sharedStoreZoneRepairLastTimeoutAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheOnLaunch)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedAt)
        defaults.removeObject(forKey: UserDefaultsKeys.resetLocalCacheArmedSource)
    }
}

// MARK: - Errors

enum CoreDataStackError: LocalizedError {
    case modelNotFound(String)
    case storeLoadFailed(Error)
    case cloudKitLoadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Core Data model '\(name)' not found in app bundle."
        case .storeLoadFailed(let error):
            return "Failed to load persistent store: \(error.localizedDescription)"
        case .cloudKitLoadFailed(let error):
            return "CloudKit store failed to load: \(error.localizedDescription). Falling back to local storage."
        }
    }
}
