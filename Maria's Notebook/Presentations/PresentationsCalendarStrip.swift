// PresentationsCalendarStrip.swift
// Calendar strip section extracted from PresentationsView

import SwiftUI
import CoreData
import OSLog

struct PresentationsCalendarStrip: View {
    private static let logger = Logger.presentations
    let days: [Date]
    @Binding var startDate: Date
    let isNonSchool: (Date) -> Bool
    let onClear: (CDLessonAssignment) -> Void
    let onSelect: (CDLessonAssignment) -> Void
    
    @Environment(\.calendar) private var calendar
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>
    
    @AppStorage(UserDefaultsKeys.presentationsCalendarShowWork) private var showWork: Bool = true

    // OPTIMIZATION: Cache work items in @State instead of fetching in a computed property.
    // The computed property was executing a DB query on every body evaluation.
    // Now fetched once in .task and refreshed via .onChange when days or showWork change.
    @State private var cachedWorkItems: [CDWorkCheckIn] = []

    private func fetchWorkItems() {
        guard showWork, let firstDay = days.first, let lastDay = days.last else {
            cachedWorkItems = []
            return
        }
        let (start, _) = AppCalendar.dayRange(for: firstDay)
        let (_, end) = AppCalendar.dayRange(for: lastDay)
        let descriptor: NSFetchRequest<CDWorkCheckIn> = NSFetchRequest(entityName: "WorkCheckIn")
        descriptor.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as CVarArg, end as CVarArg)
        do {
            cachedWorkItems = try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("Failed to fetch work items for range: \(error)")
            cachedWorkItems = []
        }
    }
    
    // Find the earliest date with a scheduled lesson (including past dates)
    private var earliestDateWithLesson: Date? {
        let scheduledDates = lessonAssignments.compactMap { la -> Date? in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return nil }
            return calendar.startOfDay(for: scheduled)
        }
        return scheduledDates.min()
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                    } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("Today") {
                        let targetDate = AgendaSchoolDayRules.computeInitialStartDate(
                            calendar: calendar, isNonSchoolDay: isNonSchool
                        )
                        
                        // If we are already grounded on the correct start date, just scroll to it.
                        // Otherwise, update startDate, which will trigger the onChange below.
                        if calendar.isDate(targetDate, inSameDayAs: startDate) {
                            if let first = days.first {
                                adaptiveWithAnimation {
                                    proxy.scrollTo(first, anchor: .leading)
                                }
                            }
                        } else {
                            startDate = targetDate
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                    } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                    
                    Button {
                        showWork.toggle()
                    } label: {
                        Image(systemName: showWork ? "checkmark.square" : "square")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showWork ? "Hide work items" : "Show work items")
                }
                .padding(.horizontal, 12)
                
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        Task {
                            await moveAllScheduledLessonsForward()
                        }
                    } label: {
                        Label("Move All Forward 1 Day", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Move all scheduled lessons forward by one school day")
                    Spacer()
                }
                .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            PresentationsDayColumn(
                                day: day,
                                allLessonAssignments: Array(lessonAssignments),
                                showWork: showWork,
                                preloadedWorkItems: cachedWorkItems,
                                onClear: onClear,
                                onSelect: onSelect
                            )
                            .id(day)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .task {
                fetchWorkItems()
                // Scroll to the first day (which is the earliest of: first lesson date or today)
                if let first = days.first {
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        Self.logger.warning("Task sleep interrupted: \(error)")
                    }
                    adaptiveWithAnimation {
                        proxy.scrollTo(first, anchor: .leading)
                    }
                }
            }
            .onChange(of: showWork) { _, _ in
                fetchWorkItems()
            }
            .onChange(of: startDate) { _, _ in
                if let first = days.first {
                    adaptiveWithAnimation {
                        proxy.scrollTo(first, anchor: .leading)
                    }
                }
            }
            .onChange(of: days) { _, _ in
                fetchWorkItems()
                // When days change, scroll to first day (earliest of: first lesson date or today)
                if let first = days.first {
                    Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                        } catch {
                            Self.logger.warning("Task sleep interrupted: \(error)")
                        }
                        adaptiveWithAnimation {
                            proxy.scrollTo(first, anchor: .leading)
                        }
                    }
                }
            }
        }
    }

    private func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = calendar.startOfDay(for: startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if !isNonSchool(cursor) { remaining -= 1 }
        }
        startDate = cursor
    }
    
    private func moveAllScheduledLessonsForward() async {
        // Find all scheduled lessons that haven't been given
        let scheduledLessons = lessonAssignments.filter { la in
            la.scheduledFor != nil && !la.isGiven
        }
        
        guard !scheduledLessons.isEmpty else { return }
        
        // Move each lesson forward by one school day
        for lesson in scheduledLessons {
            guard let currentDate = lesson.scheduledFor else { continue }
            let nextSchoolDay = await SchoolCalendar.nextSchoolDay(after: currentDate, using: viewContext)
            lesson.setScheduledFor(nextSchoolDay, using: calendar)
        }
        
        // Save changes
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save lesson schedule changes: \(error)")
        }
    }
}
