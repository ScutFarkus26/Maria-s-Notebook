import Foundation
import OSLog
import CoreData
import Observation

@Observable
@MainActor
final class WorksPlanningViewModel {
    private static let logger = Logger.work

    // UI state
    var activeSheet: ActiveSheet?
    var startDate: Date
    var scheduleDate: Date = .now
    var errorMessage: String?

    // Dependencies
    private let calendar: Calendar
    private let isNonSchoolDay: (Date) -> Bool
    private let checkInServiceFactory: (NSManagedObjectContext) -> WorkCheckInServiceProtocol

    init(
        startDate: Date,
        calendar: Calendar,
        isNonSchoolDay: @escaping (Date) -> Bool,
        checkInService: @escaping (NSManagedObjectContext) -> WorkCheckInServiceProtocol
    ) {
        self.startDate = startDate
        self.calendar = calendar
        self.isNonSchoolDay = isNonSchoolDay
        self.checkInServiceFactory = checkInService
    }

    func computeDays(window: Int) -> [Date] {
        PlanningEngine.days(from: startDate, window: window, calendar: calendar)
    }

    func computeSchoolDays(count: Int) -> [Date] {
        var result: [Date] = []
        var d = startDate
        var safety = 0
        while result.count < count && safety < 1000 {
            if !isNonSchoolDay(d) {
                result.append(d)
            }
            if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                d = next
            } else {
                break
            }
            safety += 1
        }
        return result
    }

    func moveStart(bySchoolDays days: Int) {
        startDate = AgendaSchoolDayRules.movedStart(
            bySchoolDays: days, from: startDate,
            calendar: calendar, isNonSchoolDay: isNonSchoolDay
        )
    }

    func resetToFirstSchoolDay(from date: Date) {
        startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: isNonSchoolDay)
    }

    // Fixed: calling AppCalendar directly since PlanningEngine.dayID was removed
    func dayID(_ day: Date) -> String { AppCalendar.dayID(day) }
    
    func dayName(_ day: Date) -> String { PlanningEngine.dayName(day) }
    func dayNumber(_ day: Date) -> String { PlanningEngine.dayNumber(day) }
    func dayShortLabel(_ day: Date) -> String { PlanningEngine.dayShortLabel(day) }
    func isNonSchool(_ day: Date) -> Bool { isNonSchoolDay(day) }

    func scheduleCheckIn(
        for workID: UUID, on date: Date,
        context: NSManagedObjectContext, saveCoordinator: SaveCoordinator
    ) throws {
        let service = checkInServiceFactory(context)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
        request.fetchLimit = 1
        do {
            if let work = try context.fetch(request).first {
                do {
                    _ = try service.createCheckIn(for: work, date: date, status: .scheduled, purpose: "", note: "")
                    saveCoordinator.save(context, reason: "Schedule check-in")
                } catch {
                    Self.logger.warning("Failed to create check-in: \(error)")
                }
            }
        } catch {
            Self.logger.warning("Failed to fetch WorkModel: \(error)")
        }
    }

    func markCompleted(_ ci: WorkCheckIn, context: NSManagedObjectContext, saveCoordinator: SaveCoordinator) {
        let svc = checkInServiceFactory(context)
        do {
            try svc.markCompleted(ci, note: nil, at: Date())
            saveCoordinator.save(context, reason: "Mark check-in completed")
        } catch {
            errorMessage = "Failed to mark as completed. Please try again."
        }
    }
}

enum ActiveSheet: Identifiable, Equatable {
    case schedule(workID: UUID)
    case detail(workID: UUID)
    var id: String {
        switch self {
        case .schedule(let id): return "schedule-\(id)"
        case .detail(let id): return "detail-\(id)"
        }
    }
}
