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
final class CoreDataStack {
    nonisolated static let logger = Logger.coreDataStack

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

    /// The task that forwards remote-change notifications to the handler.
    /// `nonisolated(unsafe)` so the (nonisolated) `deinit` can cancel it — it is
    /// written once during init and read once at deinit, with no concurrent
    /// access, so the unchecked annotation is safe here.
    nonisolated(unsafe) private var remoteChangeTask: Task<Void, Never>?

    /// The pending history pass for the current burst of remote-change
    /// notifications (see `handleRemoteChangeNotification`). Not `private`:
    /// the handler lives in the `+Contexts` extension.
    var pendingRemoteChangePass: Task<Void, Never>?

    /// How long notifications are collected before one history pass runs.
    /// One pass reads every transaction since the processor's token, so
    /// folding a burst into it loses nothing.
    static let remoteChangeCoalesceWindow: Duration = .milliseconds(400)

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
    ///   - localStoreURL: Optional isolated location for a local-only store. This is
    ///     used by Sample Class and tests; it is never connected to CloudKit.
    ///   - managedObjectModel: An already-loaded model to share with another stack.
    ///     Sample Class uses the primary stack's exact model instance so SwiftUI
    ///     fetch controllers remain valid while their context is replaced.
    init(
        enableCloudKit: Bool = true,
        inMemory: Bool = false,
        preserveSplitStoreLayout: Bool = false,
        localStoreURL: URL? = nil,
        managedObjectModel suppliedModel: NSManagedObjectModel? = nil
    ) throws {
        let start = Date()
        let initInterval = LaunchSignposts.begin("CoreDataStack.init")
        defer { LaunchSignposts.end("CoreDataStack.init", initInterval) }
        Self.logger.info("Initializing CoreDataStack (CloudKit: \(enableCloudKit), inMemory: \(inMemory))...")

        // Honor a deferred "Reset Local Cache" request, then note whether this
        // launch downloads everything from iCloud — both before the container
        // is created (see `prepareOnDiskStores`).
        if !inMemory, localStoreURL == nil {
            Self.prepareOnDiskStores(enableCloudKit: enableCloudKit)
        }

        // One model instance per process — see `sharedModel()`. Sample Class
        // may hand in that same instance explicitly so its NSEntityDescriptions
        // keep their identity while SwiftUI swaps the managed-object context.
        let model = try suppliedModel ?? Self.sharedModel()
        Self.setActiveModel(model)

        container = NSPersistentCloudKitContainer(name: Self.modelName, managedObjectModel: model)

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
                    url: localStoreURL ?? Self.unifiedStoreURL(),
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
        var migrationBackups: [URL: URL] = [:]
        if !inMemory {
            let prepare = LaunchSignposts.begin("PrepareStoresForLoad")
            migrationBackups = try Self.prepareStoresForLoad(container: container, model: model)
            LaunchSignposts.end("PrepareStoresForLoad", prepare)
        }

        // Load stores synchronously
        var loadErrors: [Error] = []
        let load = LaunchSignposts.begin("LoadPersistentStores")
        defer { LaunchSignposts.end("LoadPersistentStores", load) }
        container.loadPersistentStores { description, error in
            if let error {
                Self.logger.error("Failed to load store '\(description.configuration ?? "default")': \(error)")
                loadErrors.append(error)
            } else {
                Self.logger.info("Loaded store: \(description.configuration ?? "default")")
            }
        }

        if !loadErrors.isEmpty {
            // The repair did not work. Put the originals back so the next
            // attempt — and the user — see the store exactly as it was.
            for (storeURL, backupURL) in migrationBackups {
                Self.restoreStoreBackup(backupURL, to: storeURL)
            }

            // If CloudKit stores failed, try local-only fallback
            if enableCloudKit && !inMemory {
                Self.logger.warning("CloudKit store load failed, retrying without CloudKit...")
                isCloudKitActive = false
                throw CoreDataStackError.cloudKitLoadFailed(loadErrors.first!)
            }
            throw CoreDataStackError.storeLoadFailed(loadErrors.first!)
        }

        // Lightweight migration rewrites store metadata, so re-apply the
        // schema stamp now that the (possibly migrated) stores are open.
        if !inMemory {
            Self.restampSchemaVersion(in: container)
        }

        // Configure view context
        configureViewContext()

        #if DEBUG
        if enableCloudKit, !inMemory {
            initializeCloudKitSchemaIfRequested()
        }
        #endif

        // The Daybook Assistant gets neither the processor nor the listener:
        // on every remote-change burst they read history for dedup requests
        // (compiled out there) and entity notifications nothing in it observes.
        // History tracking stays on in its store descriptions; CloudKit
        // mirroring needs it.
        #if !ASSISTANT_APP
        // Create the persistent history processor — but only for the primary
        // on-disk stack. Sample Class and test stacks (localStoreURL / inMemory)
        // must not create one: all processors persist their per-store positions
        // under the same UserDefaults key, and a pass keeps positions only for
        // the stores its own container loaded, so a secondary stack's pass
        // would erase the primary stack's cursor.
        if localStoreURL == nil && !inMemory {
            historyProcessor = PersistentHistoryProcessor(container: container)
        }

        // Listen for remote changes. `NSPersistentStoreRemoteChange` fires on a
        // background queue; the notification sequence resumes this main-actor
        // task, so the handler runs on the main actor without a manual hop.
        remoteChangeTask = Task { [weak self] in
            guard let coordinator = self?.container.persistentStoreCoordinator else { return }
            let changes = NotificationCenter.default
                .notifications(named: .NSPersistentStoreRemoteChange, object: coordinator)
                .map { _ in () }
            for await _ in changes {
                self?.handleRemoteChangeNotification()
            }
        }
        #endif

        let elapsed = String(format: "%.3f", Date().timeIntervalSince(start))
        Self.logger.info("CoreDataStack initialized in \(elapsed)s")
    }

    #if DEBUG
    /// Mirrors Core Data model changes into the CloudKit development schema.
    /// Kept out of the normal launch path per Apple's workflow ("Sharing Core
    /// Data objects between iCloud users"): run the app once with the
    /// -InitializeCloudKitSchema launch argument after a model change, verify
    /// in CloudKit Console, then deploy the schema to production.
    ///
    /// Apple allows schema setup only in Development, so a schema run is a
    /// Development build whatever the project's setting: build it with
    /// `CLOUDKIT_ENVIRONMENT=Development` (which also opens the Development
    /// notebook's own store files). A Production build refuses the argument.
    private func initializeCloudKitSchemaIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") else { return }
        guard CloudKitEnvironment.allowsSchemaInitialization else {
            let refusal = "-InitializeCloudKitSchema ignored: this build syncs with Production. " +
                "Rebuild with CLOUDKIT_ENVIRONMENT=Development for a schema run."
            Self.logger.error("\(refusal, privacy: .public)")
            return
        }
        do {
            try container.initializeCloudKitSchema(options: [])
            Self.logger.info("CloudKit schema initialized from Core Data model")
        } catch {
            Self.logger.error("CloudKit schema initialization failed: \(error.localizedDescription)")
        }
    }
    #endif

    deinit {
        // The production stack lives for the whole process, but launch-time
        // fallbacks and tests create throwaway stacks; without this they leak a
        // task that keeps firing remote-change handlers on a dead stack.
        // Reading `remoteChangeTask` here is safe (see its declaration).
        remoteChangeTask?.cancel()
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
            name: "CosmicDaybookFallback",
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

}

// MARK: - Errors

enum CoreDataStackError: LocalizedError {
    case modelNotFound(String)
    case storeLoadFailed(Error)
    case cloudKitLoadFailed(Error)
    case storeFromNewerBuild(storeName: String, storeVersion: Int, appVersion: Int)
    case storeSchemaIncoherent(storeName: String, detail: String)

    /// What the person sees: plain words, no file names, codes or format
    /// numbers. Those are in `technicalDetail`, for the log and Details.
    ///
    /// In the notebook these reach only the database-error screen (a store
    /// error that isn't fatal is ridden out by the launch's fallbacks), which
    /// has the "Re-download from iCloud…" button. The Daybook Assistant
    /// compiles this file: its startup screen words these itself
    /// (`AssistantStartupProblem`), so its text here is what Siri says when
    /// a command can't open the class.
    var errorDescription: String? {
        #if ASSISTANT_APP
        switch self {
        case .modelNotFound:
            return "This copy of Daybook Assistant is damaged. Reinstall it."
        default:
            return "Daybook Assistant couldn't open your class. Open the app to fix it."
        }
        #else
        switch self {
        case .modelNotFound:
            return "This copy of Cosmic Daybook is damaged. Reinstall it."
        case .storeLoadFailed, .cloudKitLoadFailed:
            return "Cosmic Daybook couldn't open your notebook."
        case .storeFromNewerBuild:
            return "Your notebook on this device was last opened by a newer version of Cosmic Daybook. "
                + "Opening it with this copy would permanently delete the newer changes, so it was left "
                + "untouched. Quit any older copies of the app and open the current one."
        case .storeSchemaIncoherent:
            return "Your notebook on this device was damaged by an older version of the app, so it was "
                + "left untouched. Choose \u{201C}Re-download from iCloud\u{2026}\u{201D} to get a fresh copy."
        }
        #endif
    }

    /// The raw facts behind the message: store file, format numbers, the
    /// underlying error. For the log and the error screen's Details.
    var technicalDetail: String {
        switch self {
        case .modelNotFound(let name):
            return "Core Data model '\(name)' not found in app bundle."
        case .storeLoadFailed(let error):
            let nsError = error as NSError
            return "Failed to load persistent store: \(error.localizedDescription) "
                + "(\(nsError.domain) \(nsError.code))"
        case .cloudKitLoadFailed(let error):
            let nsError = error as NSError
            return "CloudKit store failed to load: \(error.localizedDescription) "
                + "(\(nsError.domain) \(nsError.code))"
        case .storeFromNewerBuild(let storeName, let storeVersion, let appVersion):
            return "\(storeName) has database format \(storeVersion); this build understands \(appVersion)."
        case .storeSchemaIncoherent(let storeName, let detail):
            return "\(storeName) is internally inconsistent (\(detail))."
        }
    }
}
