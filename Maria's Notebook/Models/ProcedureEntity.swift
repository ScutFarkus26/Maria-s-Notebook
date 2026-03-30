import Foundation
import CoreData

@objc(Procedure)
public class Procedure: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var summary: String
    @NSManaged public var content: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var icon: String
    @NSManaged public var relatedProcedureIDsRaw: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Procedure", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.summary = ""
        self.content = ""
        self.categoryRaw = ProcedureCategory.other.rawValue
        self.icon = ""
        self.relatedProcedureIDsRaw = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Enums

extension Procedure {
    enum ProcedureCategory: String, Codable, CaseIterable, Identifiable, Sendable {
        case dailyRoutines = "Daily Routines"
        case safety = "Safety & Emergency"
        case specialSchedules = "Special Schedules"
        case transitions = "Transitions"
        case materials = "Materials & Cleanup"
        case communication = "Communication"
        case behavioral = "Behavioral"
        case other = "Other"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .dailyRoutines: return "sun.horizon"
            case .safety: return "exclamationmark.shield"
            case .specialSchedules: return "calendar.badge.clock"
            case .transitions: return "arrow.left.arrow.right"
            case .materials: return "tray.2"
            case .communication: return "message"
            case .behavioral: return "hand.raised"
            case .other: return "doc.text"
            }
        }

        public var description: String {
            switch self {
            case .dailyRoutines: return "Morning arrival, lunch, dismissal, etc."
            case .safety: return "Fire drills, lockdowns, medical emergencies"
            case .specialSchedules: return "Friday schedules, early release, field trips"
            case .transitions: return "Moving between activities and spaces"
            case .materials: return "Using and caring for classroom materials"
            case .communication: return "Parent communication, announcements"
            case .behavioral: return "Conflict resolution, classroom expectations"
            case .other: return "Other classroom procedures"
            }
        }
    }
}

// MARK: - Computed Properties

extension Procedure {
    /// Computed property for category enum
    var category: ProcedureCategory {
        get { ProcedureCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Computed property for related procedure IDs
    var relatedProcedureIDs: [String] {
        get {
            guard !relatedProcedureIDsRaw.isEmpty else { return [] }
            return relatedProcedureIDsRaw.components(separatedBy: ",")
        }
        set {
            relatedProcedureIDsRaw = newValue.joined(separator: ",")
        }
    }

    /// Display icon - uses custom icon if set, otherwise category default
    var displayIcon: String {
        icon.isEmpty ? category.icon : icon
    }

    /// Updates the modification timestamp
    func touch() {
        modifiedAt = Date()
    }
}
