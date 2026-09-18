// CurriculumMapStore.swift
// Owns one loaded snapshot and the cells derived from it, cached per child.
// Loading runs on a background context; the store only ever hands out value
// types, so views never touch a managed object to draw a glyph.
//
// Invalidation: a save touching one of `CurriculumMapLoader.watchedEntityNames`
// (any context, this process) or a CloudKit remote change drops the cache and
// reloads, debounced — a sync batch lands as many saves in a row.

import CoreData
import Foundation
import OSLog

@Observable
final class CurriculumMapStore {
    private static let logger = Logger.app(category: "CurriculumMap")

    private(set) var input: CurriculumMapInput?
    private(set) var isLoading = false
    private(set) var loadedAt: Date?

    @ObservationIgnored private var cellsByStudent: [UUID: [UUID: CurriculumCell]] = [:]
    @ObservationIgnored private var allCells: [UUID: [UUID: CurriculumCell]]?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    // MARK: - Loading

    /// Loads (or reloads) the snapshot from the store behind `viewContext`.
    /// Safe to call repeatedly; a call that lands while another is in flight
    /// supersedes it.
    func load(from viewContext: NSManagedObjectContext) async {
        guard let coordinator = viewContext.persistentStoreCoordinator else { return }
        generation += 1
        let myGeneration = generation
        isLoading = input == nil
        let hiddenNames = TestStudentsFilter.normalizedHiddenNames()

        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = coordinator
        background.undoManager = nil
        var snapshot = await background.perform {
            CurriculumMapLoader.snapshot(in: background)
        }
        guard myGeneration == generation else { return }

        if !hiddenNames.isEmpty {
            snapshot.students.removeAll { hiddenNames.contains($0.fullName.normalizedForComparison()) }
        }
        input = snapshot
        cellsByStudent = [:]
        allCells = nil
        loadedAt = Date()
        isLoading = false
        Self.logger.debug(
            "Loaded curriculum map: \(snapshot.lessons.count) lessons, \(snapshot.students.count) students"
        )
    }

    /// Reload after a save, coalescing a burst of saves into one pass.
    func scheduleReload(from viewContext: NSManagedObjectContext, delay: Duration = .milliseconds(400)) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.load(from: viewContext)
        }
    }

    // MARK: - Cells

    /// The child's cells keyed by lesson; a missing lesson is not presented.
    func cells(for studentID: UUID) -> [UUID: CurriculumCell] {
        if let cached = cellsByStudent[studentID] { return cached }
        guard let input else { return [:] }
        let cells = CurriculumMapEngine.cells(for: studentID, input: input)
        cellsByStudent[studentID] = cells
        return cells
    }

    /// Every child's cells, student → lesson.
    func cellsForAllStudents() -> [UUID: [UUID: CurriculumCell]] {
        if let allCells { return allCells }
        guard let input else { return [:] }
        let cells = CurriculumMapEngine.cells(input: input)
        allCells = cells
        cellsByStudent = cells
        return cells
    }

    func student(_ id: UUID) -> CurriculumStudentRef? {
        input?.students.first { $0.id == id }
    }

    func lesson(_ id: UUID) -> CurriculumLessonRef? {
        input?.lessons.first { $0.id == id }
    }

    // MARK: - Change Notifications

    /// Entity names in a did-save notification, read off object ids so the
    /// closure is safe on the posting thread. Empty when nothing watched changed.
    nonisolated static func watchedEntities(in notification: Notification) -> Set<String> {
        let keys = [NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey, NSDeletedObjectIDsKey]
        var names = Set<String>()
        for key in keys {
            guard let ids = notification.userInfo?[key] as? Set<NSManagedObjectID> else { continue }
            for id in ids {
                if let name = id.entity.name, CurriculumMapLoader.watchedEntityNames.contains(name) {
                    names.insert(name)
                }
            }
        }
        return names
    }
}
