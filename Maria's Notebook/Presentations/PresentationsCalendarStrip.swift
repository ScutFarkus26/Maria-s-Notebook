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
            .onChange(of: startDate) { _, _ in
                if let first = days.first {
                    withAnimation {
                        proxy.scrollTo(first, anchor: .leading)
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
}

