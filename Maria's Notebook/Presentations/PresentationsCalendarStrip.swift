// PresentationsCalendarStrip.swift
// Calendar strip section extracted from PresentationsView

import SwiftUI
import SwiftData

struct PresentationsCalendarStrip: View {
    let days: [Date]
    @Binding var startDate: Date
    let isNonSchool: (Date) -> Bool
    let onClear: (StudentLesson) -> Void
    let onSelect: (StudentLesson) -> Void
    
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    
    @Query private var studentLessons: [StudentLesson]
    
    // Find the earliest date with a scheduled lesson (including past dates)
    private var earliestDateWithLesson: Date? {
        let scheduledDates = studentLessons.compactMap { sl -> Date? in
            guard let scheduled = sl.scheduledFor, !sl.isGiven else { return nil }
            return calendar.startOfDay(for: scheduled)
        }
        return scheduledDates.min()
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button { moveStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("Today") {
                        let targetDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: calendar, isNonSchoolDay: isNonSchool)
                        
                        // If we are already grounded on the correct start date, just scroll to it.
                        // Otherwise, update startDate, which will trigger the onChange below.
                        if calendar.isDate(targetDate, inSameDayAs: startDate) {
                            if let first = days.first {
                                withAnimation {
                                    proxy.scrollTo(first, anchor: .leading)
                                }
                            }
                        } else {
                            startDate = targetDate
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { moveStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
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
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            PresentationsDayColumn(
                                day: day,
                                allStudentLessons: studentLessons,
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
            .onAppear {
                // Scroll to the first day (which is the earliest of: first lesson date or today)
                if let first = days.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(first, anchor: .leading)
                        }
                    }
                }
            }
            .onChange(of: startDate) { _, _ in
                if let first = days.first {
                    withAnimation {
                        proxy.scrollTo(first, anchor: .leading)
                    }
                }
            }
            .onChange(of: days) { _, _ in
                // When days change, scroll to first day (earliest of: first lesson date or today)
                if let first = days.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
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
        let scheduledLessons = studentLessons.filter { sl in
            sl.scheduledFor != nil && !sl.isGiven
        }
        
        guard !scheduledLessons.isEmpty else { return }
        
        // Move each lesson forward by one school day
        for lesson in scheduledLessons {
            guard let currentDate = lesson.scheduledFor else { continue }
            let nextSchoolDay = await SchoolCalendar.nextSchoolDay(after: currentDate, using: modelContext)
            lesson.setScheduledFor(nextSchoolDay, using: calendar)
            #if DEBUG
            lesson.checkInboxInvariant()
            #endif
        }
        
        // Save changes
        try? modelContext.save()
    }
}

