import SwiftUI
import SwiftData

private enum DayPeriod {
    case morning
    case afternoon
}

struct PlanningWeekView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @Query private var studentLessons: [StudentLesson]
    @State private var weekStart: Date = Self.monday(for: Date())
    @State private var selectedLessonForDetail: StudentLesson? = nil
    @State private var isSidebarTargeted: Bool = false

    private var days: [Date] {
        (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }
    
    private var unscheduledLessons: [StudentLesson] {
        studentLessons.filter { $0.scheduledFor == nil && $0.givenAt == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        WeekGrid(days: days)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selectedLessonForDetail) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedLessonForDetail = nil
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Schedule")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Next lessons that still need a time slot.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if unscheduledLessons.isEmpty {
                        Spacer(minLength: 20)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("Nothing left to plan")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("All next lessons are on the calendar.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        ForEach(unscheduledLessons, id: \.id) { sl in
                            StudentLessonPill(lesson: sl)
                                .contextMenu {
                                    Button {
                                        selectedLessonForDetail = sl
                                    } label: {
                                        Label("Open Details", systemImage: "info.circle")
                                    }
                                }
                                .onTapGesture { selectedLessonForDetail = sl }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isSidebarTargeted ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 3)
        )
        .dropDestination(for: String.self, action: { items, _ in
            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            if let sl = studentLessons.first(where: { $0.id == id }) {
                sl.scheduledFor = nil
                do {
                    try modelContext.save()
                } catch {
                    return false
                }
                return true
            }
            return false
        }, isTargeted: { hovering in
            isSidebarTargeted = hovering
        })
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(weekRangeString)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Today") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    weekStart = Self.monday(for: Date(), calendar: calendar)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers
    private var weekRangeString: String {
        guard let end = calendar.date(byAdding: .day, value: 4, to: weekStart) else { return "" }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: end))"
    }

    static func monday(for date: Date, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun, 2=Mon, ...
        let daysToSubtract = (weekday + 5) % 7 // Mon->0, Tue->1, ... Sun->6
        return cal.date(byAdding: .day, value: -daysToSubtract, to: startOfDay) ?? startOfDay
    }
}

// MARK: - Week Grid
private struct WeekGrid: View {
    @Environment(\.calendar) private var calendar
    let days: [Date]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 160), spacing: 24), count: 5)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(days, id: \.self) { day in
                DayColumn(day: day)
            }
        }
    }
}

// MARK: - Day Column
private struct DayColumn: View {
    @Environment(\.calendar) private var calendar
    let day: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 2)

            // Morning
            Text("Morning")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(day: day, period: .morning)
                .frame(minHeight: 220)

            // Afternoon
            Text("Afternoon")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
            DropZone(day: day, period: .afternoon)
                .frame(minHeight: 220)
        }
    }

    private var dayName: String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: day)
    }

    private var dayNumber: String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("d")
        return fmt.string(from: day)
    }
}

// MARK: - Drop Zone
private struct DropZone: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var studentLessons: [StudentLesson]
    @State private var isTargeted: Bool = false

    let day: Date
    let period: DayPeriod

    private var scheduledLessonsForSlot: [StudentLesson] {
        studentLessons.filter { sl in
            guard let scheduled = sl.scheduledFor else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { lhs, rhs in
            (lhs.scheduledFor ?? .distantPast) < (rhs.scheduledFor ?? .distantPast)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color.primary.opacity(0.25))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .allowsHitTesting(false)

            if isTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 3)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("Drop lesson here")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledLessonsForSlot, id: \.id) { sl in
                        StudentLessonPill(lesson: sl)
                    }
                }
            }
            .padding(12)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self, action: { items, _ in
            guard let idString = items.first, let id = UUID(uuidString: idString) else { return false }
            if let sl = studentLessons.first(where: { $0.id == id }) {
                sl.scheduledFor = dateForSlot(day: day, period: period)
                do {
                    try modelContext.save()
                } catch {
                    return false
                }
                return true
            }
            return false
        }, isTargeted: { hovering in
            isTargeted = hovering
        })
    }

    private func isInSlot(_ date: Date, period: DayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning:
            return hour < 12
        case .afternoon:
            return hour >= 12
        }
    }

    private func dateForSlot(day: Date, period: DayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int
        switch period {
        case .morning:
            hour = 9 // 9 AM for morning
        case .afternoon:
            hour = 14 // 2 PM for afternoon
        }
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }
}

private struct StudentLessonPill: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lessons: [Lesson]
    let lesson: StudentLesson
    private var lessonName: String {
        lessons.first(where: { $0.id == lesson.lessonID })?.name ?? "Lesson"
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill").foregroundStyle(.tint)
            Text(lessonName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            if !lesson.studentIDs.isEmpty {
                Text("• \(lesson.studentIDs.count) student\(lesson.studentIDs.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .draggable(lesson.id.uuidString)
    }
}

#Preview {
    PlanningWeekView()
        .frame(minWidth: 1000, minHeight: 600)
}

