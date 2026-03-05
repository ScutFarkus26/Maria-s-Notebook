import Foundation
import OSLog
import SwiftData
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
    private let checkInServiceFactory: (ModelContext) -> WorkCheckInService

    init(
        startDate: Date,
        calendar: Calendar,
        isNonSchoolDay: @escaping (Date) -> Bool,
        checkInService: @escaping (ModelContext) -> WorkCheckInService
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
        context: ModelContext, saveCoordinator: SaveCoordinator
    ) throws {
        let service = checkInServiceFactory(context)
        var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
        descriptor.fetchLimit = 1
        do {
            if let work = try context.fetch(descriptor).first {
                do {
                    _ = try service.createCheckIn(for: work, date: date, status: .scheduled, purpose: "", note: "")
                    _ = saveCoordinator.save(context, reason: "Schedule check-in")
                } catch {
                    Self.logger.warning("Failed to create check-in: \(error)")
                }
            }
        } catch {
            Self.logger.warning("Failed to fetch WorkModel: \(error)")
        }
    }

    func markCompleted(_ ci: WorkCheckIn, context: ModelContext, saveCoordinator: SaveCoordinator) {
        let svc = checkInServiceFactory(context)
        do {
            try svc.markCompleted(ci)
            _ = saveCoordinator.save(context, reason: "Mark check-in completed")
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
