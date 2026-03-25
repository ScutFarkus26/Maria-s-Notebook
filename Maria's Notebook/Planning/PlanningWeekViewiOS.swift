import SwiftUI
import SwiftData
import OSLog
#if DEBUG
import Foundation
#endif

/// iOS version of PlanningWeekView using manual FetchDescriptor for battery optimization.
/// On iPhone, we fetch data on-demand to save battery and memory instead of maintaining
/// constant @Query monitoring.
@MainActor
struct PlanningWeekViewiOS: View {
    private static let logger = Logger.planning
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    
    // Manual fetch - loaded on-demand to save battery
    // Migrated to LessonAssignment
    @State private var inboxLessons: [LessonAssignment] = []
    @State private var lessons: [Lesson] = []
    @State private var students: [Student] = []
    
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
            DataMigrations.deduplicateDraftLessonAssignments(using: modelContext)
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: inboxLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
    }
    
    // MARK: - Data Loading
    
    // Manually fetch data using FetchDescriptor instead of @Query
    // swiftlint:disable:next function_body_length
    private func loadData() {
        #if DEBUG
        let startTime = Date()
        #endif
        
        // Fetch unscheduled inbox lessons (migrated to LessonAssignment)
        let inboxDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate<LessonAssignment> { $0.scheduledFor == nil && $0.presentedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            inboxLessons = try modelContext.fetch(inboxDescriptor)
        } catch {
            Self.logger.warning("Failed to fetch inbox lessons: \(error, privacy: .public)")
            inboxLessons = []
        }

        // Fetch all lessons (needed for lookups and relationships)
        let lessonsDescriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\.name)]
        )
        do {
            lessons = try modelContext.fetch(lessonsDescriptor)
        } catch {
            Self.logger.warning("Failed to fetch lessons: \(error, privacy: .public)")
            lessons = []
        }

        // Fetch all students (needed for relationships)
        let studentsDescriptor = FetchDescriptor<Student>(
            sortBy: [
                SortDescriptor(\.lastName),
                SortDescriptor(\.firstName)
            ]
        )
        do {
            students = try modelContext.fetch(studentsDescriptor)
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
        
        DataMigrations.deduplicateDraftLessonAssignments(using: modelContext)
    }
    
    // MARK: - Helpers
    
    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    /// Rules:
    /// - Explicit NonSchoolDay records mark weekdays as non-school
    /// - Weekends are non-school by default unless a SchoolDayOverride exists for that date
    private func isNonSchoolDay(_ day: Date) -> Bool {
        let day = calendar.startOfDay(for: day)

        // 1) Explicit non-school day wins
        do {
            var nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            nsDescriptor.fetchLimit = 1
            let nonSchoolDays: [NonSchoolDay] = try modelContext.fetch(nsDescriptor)
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
            var ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            ovDescriptor.fetchLimit = 1
            let overrides: [SchoolDayOverride] = try modelContext.fetch(ovDescriptor)
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
        
        // Fetch only future scheduled lessons to find the next one (using LessonAssignment)
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.scheduledFor != nil && $0.presentedAt == nil },
            sortBy: [SortDescriptor(\.scheduledFor)]
        )
        descriptor.fetchLimit = 1
        
        if let nextUp = modelContext.safeFetchFirst(descriptor),
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
        let baseIDs = inboxLessons.map { $0.id }
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = inboxLessons
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.id }
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
}
