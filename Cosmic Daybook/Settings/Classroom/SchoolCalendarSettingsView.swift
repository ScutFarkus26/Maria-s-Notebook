import SwiftUI
import CoreData
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The School year card: when the year starts, which year it is, and what
/// the day counters count from.
struct SchoolYearStartSettingsView: View {
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        SchoolYearStartConfig(store: dependencies.schoolYearStore)
    }
}

/// The Days off card: the month grid and "Clear this month".
struct SchoolCalendarSettingsView: View {
    private static let logger = Logger.settings
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    @Environment(\.dependencies) private var dependencies
    @State private var currentMonth: Date = Date()
    @State private var nonSchoolDates: Set<Date> = []
    /// The month's days off that "Clear this month" would remove, counted with
    /// each reload so the confirmation can name the number.
    @State private var daysOffCount = 0
    @State private var confirmingClear = false

    private var monthInterval: DateInterval {
        let cal = calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? Date()
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.small) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Text(monthTitle(currentMonth))
                    .font(.headline)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                Spacer()
                Label("\(PlatformVerb.tap) dates to mark as non-school", systemImage: PlatformVerb.tapSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CalendarMonthGridView(
                month: currentMonth,
                onDateToggled: { date, isNonSchool in
                    let day = calendar.startOfDay(for: date)
                    if isNonSchool {
                        nonSchoolDates.insert(day)
                    } else {
                        nonSchoolDates.remove(day)
                    }
                    daysOffCount = countDaysOff()
                },
                nonSchoolDates: nonSchoolDates
            )

            .frame(maxWidth: .infinity)

            Button(role: .destructive) {
                confirmingClear = true
            } label: {
                Label("Clear this month", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(daysOffCount == 0)
            .padding(.top, AppTheme.Spacing.xsmall)
            .confirmationDialog(clearTitle, isPresented: $confirmingClear, titleVisibility: .visible) {
                Button(daysOffCount == 1 ? "Clear 1 day off" : "Clear \(daysOffCount) days off", role: .destructive) {
                    clearMonth()
                }
            } message: {
                Text("They go back to being school days, here and in your assistant's attendance.")
            }
        }
        .task {
            await reload()
        }
        // Days off marked on another device arrive through iCloud while this
        // card is open. NonSchoolDay and SchoolDayOverride aren't among the
        // entities `onPresentationDataChange` watches; the history processor
        // posts `.schoolDayDataDidChange` for exactly those two instead.
        .onReceive(NotificationCenter.default.publisher(for: .schoolDayDataDidChange)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        let range = monthInterval.start ..< monthInterval.end
        nonSchoolDates = await SchoolCalendarService.shared.nonSchoolDays(in: range, using: viewContext)
        daysOffCount = countDaysOff()
    }

    /// "Clear 4 days off in October?"
    private var clearTitle: String {
        let month = currentMonth.formatted(.dateTime.month(.wide))
        return daysOffCount == 1 ? "Clear 1 day off in \(month)?" : "Clear \(daysOffCount) days off in \(month)?"
    }

    /// The days marked off in the month on screen.
    private var monthDaysOffRequest: NSFetchRequest<CDNonSchoolDay> {
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            monthInterval.start as NSDate, monthInterval.end as NSDate
        )
        return request
    }

    private func countDaysOff() -> Int {
        do {
            return try viewContext.count(for: monthDaysOffRequest)
        } catch {
            Self.logger.warning("Failed to count non-school days: \(error, privacy: .public)")
            return 0
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = newDate
            Task {
                await reload()
            }
        }
    }

    private func monthTitle(_ date: Date) -> String {
        DateFormatters.localizedMonthYear.string(from: date)
    }

    private func clearMonth() {
        do {
            for day in try viewContext.fetch(monthDaysOffRequest) {
                viewContext.delete(day)
            }
        } catch {
            Self.logger.warning("Failed to fetch non-school days: \(error, privacy: .public)")
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Update school calendar")
        // Its `.schoolDayDataDidChange` reloads this grid too.
        SchoolCalendarService.notifySchoolDayDataChanged()
    }
}

/// The New year card: the rollover, the carried-over year plans, and the
/// grade each age lands in.
struct NewSchoolYearSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingRollover = false
    @State private var showingCarryOverSweep = false
    /// Counted on appear and after the sweep closes, never in `body`: the count
    /// is a fetch per enrolled child.
    @State private var carryOverBadge: Int?
    @TestStudentVisibility private var testStudents

    private static let guidelines: [(age: String, grade: String)] = [
        ("Under 6", "Kindergarten"), ("Age 6", "1st Grade"), ("Age 7", "2nd Grade"),
        ("Age 8", "3rd Grade"), ("Age 9", "4th Grade"), ("Age 10", "5th Grade"),
        ("Age 11", "6th Grade"), ("Age 12", "7th Grade"), ("Age 13", "8th Grade"),
        ("Age 14+", "Graduated")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showingRollover = true
            } label: {
                SettingsLinkRow(title: "School year rollover", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.plain)
            .help("Promote, transfer, or withdraw students for the new school year")
            .sheet(isPresented: $showingRollover) {
                SchoolYearRolloverView()
                    #if os(macOS)
                    .frame(minWidth: 640, minHeight: 560)
                    #endif
            }

            Divider()

            carryOverSweepRow

            Divider()
                .padding(.bottom, AppTheme.Spacing.small)

            gradeGuidelines
        }
    }

    /// Year-plan targets left over from a school year that has ended. The
    /// count is this year's outstanding entries and disappears once the sweep
    /// has been run; the row itself always stays, since a plan can go stale
    /// again and re-dating is not a one-shot migration.
    private var carryOverSweepRow: some View {
        Button {
            showingCarryOverSweep = true
        } label: {
            SettingsLinkRow(
                title: "Carried-over year plans",
                systemImage: "calendar.badge.exclamationmark",
                detail: carryOverBadge.map { $0.formatted() }
            )
        }
        .buttonStyle(.plain)
        .help("Re-date or skip year-plan targets left over from a school year that has ended")
        .sheet(isPresented: $showingCarryOverSweep, onDismiss: refreshCarryOverBadge) {
            CarriedOverPlanSweepView()
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 480)
                #endif
        }
        .task { refreshCarryOverBadge() }
    }

    private func refreshCarryOverBadge() {
        carryOverBadge = CarriedOverPlanSweepViewModel.badgeCount(
            context: viewContext,
            showTestStudents: testStudents.show,
            testStudentNames: testStudents.namesRaw
        )
    }

    private var gradeGuidelines: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Label("Grade guidelines (Florida)", systemImage: "graduationcap.fill")
                .font(.subheadline.weight(.semibold))

            Text("Grade assignments based on student age as of September 1st")
                .font(.footnote)
                .foregroundStyle(.secondary)

            #if os(macOS)
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: AppTheme.Spacing.xsmall) {
                ForEach(Self.guidelines, id: \.age) { row in
                    GradeGuidelineRowCompact(age: row.age, grade: row.grade)
                }
            }
            .padding(.top, AppTheme.Spacing.xsmall)
            #else
            VStack(spacing: 10) {
                ForEach(Self.guidelines, id: \.age) { row in
                    GradeGuidelineRow(age: row.age, grade: row.grade)
                }
            }
            #endif
        }
    }
}

private struct GradeGuidelineRow: View {
    let age: String
    let grade: String
    
    private var backgroundColor: Color {
        Color.controlBackgroundColor()
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Text(age)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            
            Text(grade)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.compact)
        .surface(UIConstants.CornerRadius.medium, fill: backgroundColor)
    }
}

#if os(macOS)
private struct GradeGuidelineRowCompact: View {
    let age: String
    let grade: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            Text(age)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("→")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(grade)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
