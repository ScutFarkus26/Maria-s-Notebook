import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

/// macOS version of PlanningWeekView using @Query for automatic, real-time updates.
/// The Mac has the power to handle automatic query monitoring, providing instant updates.
@MainActor
struct PlanningWeekViewMac: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter
    @Environment(\.modelContext) private var modelContext
    
    // Magic @Query - automatically updates when data changes
    @Query(filter: #Predicate<StudentLesson> { $0.scheduledFor == nil && $0.isGiven == false })
    private var inboxLessons: [StudentLesson]
    
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    
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
            onRefreshNeeded: nil // Not needed - @Query handles updates automatically
        )
        .onAppear {
            #if DEBUG
            print("🚀 PlanningWeekViewMac loaded with \(inboxLessons.count) inbox items (Using @Query magic)")
            PerformanceLogger.logScreenLoad(
                screenName: "PlanningWeekViewMac",
                itemCounts: [
                    "inboxLessons": inboxLessons.count,
                    "lessons": lessons.count,
                    "students": students.count
                ]
            )
            #endif
            
            // Run migrations once
            DataMigrations.normalizeGivenAtToDateOnlyIfNeeded(using: modelContext)
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            
            // Calculate initial start date
            computeInitialStartDate()
            syncInboxOrderWithCurrentBase()
        }
        .onChange(of: appRouter.planningInboxRefreshTrigger) { _, _ in
            // Keep inbox and week grid in sync after external changes
            DataMigrations.deduplicateUnpresentedStudentLessons(using: modelContext)
            syncInboxOrderWithCurrentBase()
        }
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

