//
//  PresentationRepository.swift
//  Cosmic Daybook
//
//  Repository for CDLessonAssignment (Presentation) CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct PresentationRepository: SavingRepository {
    typealias Model = CDLessonAssignment

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDLessonAssignment by ID
    func fetchLessonAssignment(id: UUID) -> CDLessonAssignment? { fetch(id: id) }

}
