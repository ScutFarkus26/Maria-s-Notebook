import SwiftUI
import CoreData
import OSLog
#if DEBUG
import Foundation
#endif

/// iOS version of PlanningWeekView using manual NSFetchRequest for battery optimization.
/// On iPhone, we fetch data on-demand to save battery and memory instead of maintaining
/// constant @Query monitoring.
@MainActor
struct PlanningWeekViewiOS: View {
    private static let logger = Logger.planning
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var viewContext
    
    // Manual fetch - loaded on-demand to save battery
    // Migrated to CDLessonAssignment
    @State private var inboxLessons: [CDLessonAssignment] = []
    @State private var lessons: [CDLesson] = []
    @State private var students: [CDStudent] = []
    
    @AppStorage(UserDefaultsKeys.planningInboxOrder) private var inboxOrderRaw: String = ""
    @State private var startDate: Date = Date()
    @State private var activeSheet: PlanningWeekViewContent.ActiveSheet?
    
    var body: some View {
        PlanningWeekViewContent(
            inboxLessons: inboxLessons,
            lessons: lessons,
            students: students,
            inboxOrderRaw: $inboxOrderRaw,
            startDate: $startDate,
            activeSheet: $activeSheet,
            onRefreshNeeded: {
                loadData()
            }
        )
        .onAppear {
            loadData()
            computeInitialStartDate()
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Reload data when external changes occur
            loadData()
            DataMigrations.deduplicateDraftLessonAssignments(using: viewContext)
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: inboxLessons.map(\.id)) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
    }
    
    // MARK: - Data Loading
    
    // Manually fetch data using NSFetchRequest instead of @Query
    // swiftlint:disable:next function_body_length
    private func loadData() {
        #if DEBUG
        let startTime = Date()
        #endif
        
        // Fetch unscheduled inbox lessons (migrated to CDLessonAssignment)
        let inboxDescriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        inboxDescriptor.predicate = NSPredicate(format: "scheduledFor == nil AND presentedAt == nil")
        inboxDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        do {
            inboxLessons = try viewContext.fetch(inboxDescriptor)
        } catch {
            Self.logger.warning("Failed to fetch inbox lessons: \(error, privacy: .public)")
            inboxLessons = []
        }

        // Fetch all lessons (needed for lookups and relationships)
        let lessonsDescriptor: NSFetchRequest<CDLesson> = NSFetchRequest(entityName: "Lesson")
        lessonsDescriptor.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        do {
            lessons = try viewContext.fetch(lessonsDescriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error, privacy: .public)")
            lessons = []
        }

        // Fetch all students (needed for relationships)
        let studentsDescriptor: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
        studentsDescriptor.sortDescriptors = [
                NSSortDescriptor(key: "lastName", ascending: true),
                NSSortDescriptor(key: "firstName", ascending: true)
            ]
        do {
            students = try viewContext.fetch(studentsDescriptor)
        } catch {
            Self.logger.warning("Failed to fetch students: \(error, privacy: .public)")
            students = []
        }

        #if DEBUG
        let loadTime = Date().timeIntervalSince(startTime)
        let inboxCount = self.inboxLessons.count
        let lessonCount = self.lessons.count
        let studentCount = self.students.count
        let timeStr = String(format: "%.3f", loadTime)
        Self.logger.debug(
            """
            PlanningWeekViewiOS loaded \
            \(inboxCount, privacy: .public) inbox, \
            \(lessonCount, privacy: .public) lessons, \
            \(studentCount, privacy: .public) students \
            in \(timeStr)s
            """
        )
        PerformanceLogger.logScreenLoad(
            screenName: "PlanningWeekViewiOS",
            itemCounts: [
                "inboxLessons": inboxLessons.count,
                "lessons": lessons.count,
                "students": students.count
            ]
        )
        #endif
        
        DataMigrations.deduplicateDraftLessonAssignments(using: viewContext)
    }
    
    // MARK: - Helpers
    
    /// Synchronous helper that determines if a date is a non-school day using direct NSManagedObjectContext fetches.
    /// Rules:
    /// - Explicit CDNonSchoolDay records mark weekdays as non-school
    /// - Weekends are non-school by default unless a CDSchoolDayOverride exists for that date
    private func isNonSchoolDay(_ day: Date) -> Bool {
        let day = calendar.startOfDay(for: day)

        // 1) Explicit non-school day wins
        do {
            var nsDescriptor = { let r = NSFetchRequest<CDNonSchoolDay>(entityName: "NonSchoolDay"); r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 0; return r }()
            nsDescriptor.fetchLimit = 1
            let nonSchoolDays: [CDNonSchoolDay] = try viewContext.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            // On fetch error, fall back to weekend logic below
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            var ovDescriptor = { let r = NSFetchRequest<CDSchoolDayOverride>(entityName: "SchoolDayOverride"); r.predicate = NSPredicate(format: "date == %@", day as CVarArg); r.fetchLimit = 0; return r }()
            ovDescriptor.fetchLimit = 1
            let overrides: [CDSchoolDayOverride] = try viewContext.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            // If override fetch fails, assume weekend remains non-school
        }
        return true
    }
    
    private func firstSchoolDay(onOrAfter date: Date) -> Date {
        var cursor = calendar.startOfDay(for: date)
        while isNonSchoolDay(cursor) {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cursor
    }
    
    private func computeInitialStartDate() {
        let today = calendar.startOfDay(for: Date())
        
        // Fetch only future scheduled lessons to find the next one (using CDLessonAssignment)
        var descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "scheduledFor != nil AND presentedAt == nil")
        descriptor.sortDescriptors = [NSSortDescriptor(key: "scheduledFor", ascending: true)]
        descriptor.fetchLimit = 1
        
        if let nextUp = viewContext.safeFetchFirst(descriptor),
           let date = nextUp.scheduledFor {
            let start = calendar.startOfDay(for: date)
            if start >= today && !isNonSchoolDay(start) {
                self.startDate = start
                return
            }
        }
        
        self.startDate = firstSchoolDay(onOrAfter: today)
    }
    
    @MainActor
    private func syncInboxOrderWithCurrentBase() {
        let baseIDs = inboxLessons.compactMap(\.id)
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = inboxLessons
            .filter { guard let id = $0.id else { return false }; return !order.contains(id) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .compactMap(\.id)
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
}
