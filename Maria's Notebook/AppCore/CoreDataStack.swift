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
    private static let logger = Logger.app(category: "CoreDataStack")

    // MARK: - Container

    let container: NSPersistentCloudKitContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Whether CloudKit sync is active (vs local-only fallback).
    private(set) var isCloudKitActive: Bool = false

    // MARK: - Store Configurations

    /// Configuration name for the private (per-teacher) store.
    static let privateConfiguration = "Private"
    /// Configuration name for the shared (classroom) store.
    static let sharedConfiguration = "Shared"

    // MARK: - Entity Routing

    /// Entities stored in the shared (classroom) store.
    /// These are owned by the lead guide and shared via CKShare with assistants.
    static let sharedEntityNames: Set<String> = [
        "Student",
        "Lesson",
        "LessonAttachment",
        "LessonPresentation",
        "Track",
        "TrackStep",
        "GroupTrack",
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
        "TransitionPlan",
        "TransitionChecklistItem",
        "CalendarNote",
        "SampleWork",
        "SampleWorkStep",
        "ClassroomMembership"
    ]

    /// Entities stored in the private (per-teacher) store.
    /// Each teacher has their own copy of these records.
    static let privateEntityNames: Set<String> = [
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
        "Document"
    ]

    // MARK: - Store URLs

    /// Directory for Core Data store files.
    static func storeDirectory() -> URL {
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

    static func privateStoreURL() -> URL {
        storeDirectory().appendingPathComponent("private.sqlite")
    }

    static func sharedStoreURL() -> URL {
        storeDirectory().appendingPathComponent("shared.sqlite")
    }

    // MARK: - Initialization

    /// Creates the Core Data stack.
    ///
    /// - Parameters:
    ///   - enableCloudKit: Whether to enable CloudKit sync. Defaults to the user's preference.
    ///   - inMemory: If true, uses in-memory stores (for testing/fallback).
    init(enableCloudKit: Bool = true, inMemory: Bool = false) throws {
        let start = Date()
        Self.logger.info("Initializing CoreDataStack (CloudKit: \(enableCloudKit), inMemory: \(inMemory))...")

        let modelName = "MariasNotebook"
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw CoreDataStackError.modelNotFound(modelName)
        }

        // Validate that all entities in our routing tables exist in the model
        Self.validateEntityRouting(model: model)

        container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)

        // Build store descriptions
        let privateDesc: NSPersistentStoreDescription
        let sharedDesc: NSPersistentStoreDescription

        if inMemory {
            privateDesc = Self.makeInMemoryDescription(configuration: Self.privateConfiguration)
            sharedDesc = Self.makeInMemoryDescription(configuration: Self.sharedConfiguration)
        } else {
            privateDesc = Self.makeStoreDescription(
                url: Self.privateStoreURL(),
                configuration: Self.privateConfiguration
            )
            sharedDesc = Self.makeStoreDescription(
                url: Self.sharedStoreURL(),
                configuration: Self.sharedConfiguration
            )
        }

        // Assign entities to configurations
        Self.assignEntitiesToConfigurations(model: model)

        // Enable history tracking and remote change notifications on both stores
        Self.enableHistoryTracking(privateDesc)
        Self.enableHistoryTracking(sharedDesc)

        if enableCloudKit && !inMemory {
            Self.configureCloudKit(privateDescription: privateDesc, sharedDescription: sharedDesc)
            isCloudKitActive = true
        }

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        // Load stores synchronously
        var loadErrors: [Error] = []
        container.loadPersistentStores { description, error in
            if let error {
                Self.logger.error("Failed to load store '\(description.configuration ?? "?")': \(error)")
                loadErrors.append(error)
            } else {
                Self.logger.info("Loaded store: \(description.configuration ?? "?")")
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

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        let elapsed = String(format: "%.3f", Date().timeIntervalSince(start))
        Self.logger.info("CoreDataStack initialized in \(elapsed)s")
    }

    // MARK: - View Context Configuration

    private func configureViewContext() {
        let ctx = container.viewContext
        // Automatically merge remote changes into the view context
        ctx.automaticallyMergesChangesFromParent = true
        // Last-writer-wins: remote property values override local on conflict
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // Disable autosave — we use explicit saves via SaveCoordinator
        // (Mirrors the existing SwiftData behavior where autosave was disabled)
    }

    // MARK: - Background Context

    /// Creates a new background context for batch operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return ctx
    }

    // MARK: - Remote Change Handling

    @objc private func handleRemoteChange(_ notification: Notification) {
        Self.logger.debug("Remote store change received")
        // NSPersistentCloudKitContainer + automaticallyMergesChangesFromParent handles
        // merging remote changes into the view context automatically.
        // Phase 6 will add persistent history processing and dedup here.
    }

    // MARK: - Store Description Builders

    private static func makeStoreDescription(
        url: URL,
        configuration: String
    ) -> NSPersistentStoreDescription {
        let desc = NSPersistentStoreDescription(url: url)
        desc.configuration = configuration
        desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        return desc
    }

    private static func makeInMemoryDescription(
        configuration: String
    ) -> NSPersistentStoreDescription {
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.configuration = configuration
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
    private static func assignEntitiesToConfigurations(model: NSManagedObjectModel) {
        let allEntities = model.entities

        let sharedEntities = allEntities.filter { sharedEntityNames.contains($0.name ?? "") }
        let privateEntities = allEntities.filter { privateEntityNames.contains($0.name ?? "") }

        model.setEntities(sharedEntities, forConfigurationName: sharedConfiguration)
        model.setEntities(privateEntities, forConfigurationName: privateConfiguration)

        logger.info("Entity routing: \(privateEntities.count) private, \(sharedEntities.count) shared")
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
    static func resetStores() throws {
        let fm = FileManager.default
        for url in [privateStoreURL(), sharedStoreURL()] {
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
