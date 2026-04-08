// WorkCycleSessionEntity.swift
// Core Data entity for a Montessori work cycle session (typically 3-hour uninterrupted work period).

import Foundation
import CoreData

@objc(CDWorkCycleSession)
public class CDWorkCycleSession: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var date: Date?
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var statusRaw: String
    @NSManaged public var notes: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "WorkCycleSession", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.date = Date()
        self.startTime = Date()
        self.endTime = nil
        self.statusRaw = CycleStatus.active.rawValue
        self.notes = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Computed Properties

extension CDWorkCycleSession {
    var status: CycleStatus {
        get { CycleStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            modifiedAt = Date()
        }
    }

    var isActive: Bool { status == .active }
    var isPaused: Bool { status == .paused }
    var isCompleted: Bool { status == .completed }

    /// Duration in seconds, computed from start/end times.
    var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    /// Formatted duration string (e.g., "2h 15m").
    var durationFormatted: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
