import SwiftUI
import SwiftData
import OSLog
#if DEBUG
import Foundation
#endif

/// macOS version of PlanningWeekView using @Query for automatic, real-time updates.
/// The Mac has the power to handle automatic query monitoring, providing instant updates.
@MainActor
struct PlanningWeekViewMac: View {
    private static let logger = Logger.planning
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Magic @Query - automatically updates when data changes
    // Migrated to LessonAssignment: fetch draft and unscheduled presentations
    @Query(filter: #Predicate<LessonAssignment> { $0.scheduledFor == nil && $0.presentedAt == nil })
    private var inboxLessons: [LessonAssignment]

    @Query private var lessons: [Lesson]
    @Query private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(
            studentsRaw.uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

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
            onRefreshNeeded: nil // Not needed - @Query handles updates automatically
        )
        .task {
            #if DEBUG
            let count = self.inboxLessons.count
            Self.logger.info("PlanningWeekViewMac loaded with \(count) inbox items (Using @Query magic)")
            PerformanceLogger.logScreenLoad(
                screenName: "PlanningWeekViewMac",
                itemCounts: [
                    "inboxLessons": inboxLessons.count,
                    "lessons": lessons.count,
                    "students": students.count
                ]
            )
            #endif
            
            DataMigrations.deduplicateDraftLessonAssignments(using: modelContext)
            
            // Calculate initial start date
            await computeInitialStartDate()
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Keep inbox and week grid in sync after external changes
            DataMigrations.deduplicateDraftLessonAssignments(using: modelContext)
            syncInboxOrderWithCurrentBase()
        }
    }
    
    // MARK: - Helpers
    
    private func isNonSchoolDay(_ day: Date) async -> Bool {
        await SchoolCalendar.isNonSchoolDay(day, using: modelContext)
    }
    
    private func firstSchoolDay(onOrAfter date: Date) async -> Date {
        var cursor = calendar.startOfDay(for: date)
        while await isNonSchoolDay(cursor) {
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return cursor
    }
    
    private func computeInitialStartDate() async {
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
            let isNonSchool = await isNonSchoolDay(start)
            if start >= today && !isNonSchool {
                self.startDate = start
                return
            }
        }
        
        self.startDate = await firstSchoolDay(onOrAfter: today)
    }
    
    @MainActor
    private func syncInboxOrderWithCurrentBase() {
        let baseIDs = inboxLessons.map(\.id)
        var order = InboxOrderStore.parse(inboxOrderRaw).filter { baseIDs.contains($0) }
        let missing = inboxLessons
            .filter { !order.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)
        order.append(contentsOf: missing)
        inboxOrderRaw = InboxOrderStore.serialize(order)
    }
}
