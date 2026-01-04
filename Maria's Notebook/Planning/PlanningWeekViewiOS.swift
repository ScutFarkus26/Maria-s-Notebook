import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

/// iOS version of PlanningWeekView using manual FetchDescriptor for battery optimization.
/// On iPhone, we fetch data on-demand to save battery and memory instead of maintaining
/// constant @Query monitoring.
@MainActor
struct PlanningWeekViewiOS: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    
    // Manual fetch - loaded on-demand to save battery
    @State private var inboxLessons: [StudentLesson] = []
    @State private var lessons: [Lesson] = []
    @State private var students: [Student] = []
    
    @AppStorage("PlanningInbox.order") private var inboxOrderRaw: String = ""
    @State private var startDate: Date = Date()
    @State private var activeSheet: PlanningWeekViewContent.ActiveSheet? = nil
    
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
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: inboxLessons.map { $0.id }) { _, _ in
            syncInboxOrderWithCurrentBase()
        }
    }
    
    // MARK: - Data Loading
    
    /// Manually fetch data using FetchDescriptor instead of @Query
    private func loadData() {
        #if DEBUG
        let startTime = Date()
        #endif
        
        // Fetch unscheduled inbox lessons
        let inboxDescriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate<StudentLesson> { $0.scheduledFor == nil && $0.isGiven == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        inboxLessons = (try? modelContext.fetch(inboxDescriptor)) ?? []
        
        // Fetch all lessons (needed for lookups and relationships)
        let lessonsDescriptor = FetchDescriptor<Lesson>(
            sortBy: [SortDescriptor(\.name)]
        )
        lessons = (try? modelContext.fetch(lessonsDescriptor)) ?? []
        
        // Fetch all students (needed for relationships)
        let studentsDescriptor = FetchDescriptor<Student>(
            sortBy: [
                SortDescriptor(\.lastName),
                SortDescriptor(\.firstName)
            ]
        )
        students = (try? modelContext.fetch(studentsDescriptor)) ?? []
        
        #if DEBUG
        let loadTime = Date().timeIntervalSince(startTime)
        print("📱 PlanningWeekViewiOS loaded \(inboxLessons.count) inbox items, \(lessons.count) lessons, \(students.count) students in \(String(format: "%.3f", loadTime))s (Manual fetch)")
        PerformanceLogger.logScreenLoad(
            screenName: "PlanningWeekViewiOS",
            itemCounts: [
                "inboxLessons": inboxLessons.count,
                "lessons": lessons.count,
                "students": students.count
            ]
        )
        #endif
        
        // Run migrations once on first load
        DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: modelContext)
        DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
    }
    
    // MARK: - Helpers
    
    private func isNonSchoolDay(_ day: Date) -> Bool {
        SchoolCalendar.isNonSchoolDay(day, using: modelContext)
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
        
        // Fetch only future scheduled lessons to find the next one
        var descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.scheduledFor != nil && $0.isGiven == false },
            sortBy: [SortDescriptor(\.scheduledFor)]
        )
        descriptor.fetchLimit = 1
        
        if let nextUp = try? modelContext.fetch(descriptor).first,
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

