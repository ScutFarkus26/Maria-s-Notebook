// PresentationPlannerCard.swift
// Calmer replacement for `PresentationPill` used inside the redesigned
// Presentations planner (ReadyToPresentSection and WeekDayColumn). The old
// pill is still used by 6 other call sites and is left untouched. Named
// `Planner` to avoid colliding with `Students/PresentationCard.swift` which
// is the student-screen list cell.

import SwiftUI
import CoreData

struct PresentationPlannerCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    let snapshot: LessonAssignmentSnapshot
    /// `day` controls absence/double-booked context. For inbox usage (where the
    /// presentation isn't scheduled to a particular day), pass `nil`.
    let day: Date?
    /// Optional caches — pass them when the parent already has these arrays
    /// (e.g. `ReadyToPresentSection` via `PresentationsViewModel`). When `nil`,
    /// the card falls back to its own @FetchRequest (used by `WeekDayColumn`).
    let cachedLessons: [CDLesson]?
    let cachedStudents: [CDStudent]?
    let blockingWork: [UUID: CDWorkModel]
    /// Children the caller has already found to be booked twice. In the
    /// calendar that means twice in *this card's own half* of the day, so the
    /// set arrives scoped and the card only draws what it is handed.
    let doubleBookedStudentIDs: Set<UUID>
    /// When non-nil and `totalCount > 1`, renders a readiness progress bar and
    /// count in the card footer. Pass both or neither.
    var readyCount: Int?
    var totalCount: Int?
    /// Which half of the day this card is scheduled in, shown as AM or PM.
    /// Nil where the question does not arise — the inbox, and the drag preview
    /// of something on its way out of it.
    var period: DayPeriod?

    @FetchRequest(sortDescriptors: []) private var lessonsQuery: FetchedResults<CDLesson>
    @FetchRequest(sortDescriptors: []) private var studentsQuery: FetchedResults<CDStudent>

    @State private var attendanceCache: [UUID: AttendanceStatus] = [:]
    @State private var lastAttendanceDay: Date?

    private var lessons: [CDLesson] { cachedLessons ?? Array(lessonsQuery) }
    private var students: [CDStudent] { cachedStudents ?? Array(studentsQuery) }

    // MARK: - Derived

    private var lessonObject: CDLesson? {
        lessons.first { $0.id == snapshot.lessonID }
    }

    private var lessonName: String {
        if let name = lessonObject?.name.trimmed(), !name.isEmpty { return name }
        return "Lesson \(snapshot.lessonID.uuidString.prefix(6))"
    }

    private var areaColor: Color {
        if let area = lessonObject?.area, !area.isEmpty {
            return AppColors.color(forArea: area)
        }
        return .accentColor
    }

    private var ageInSchoolDays: Int {
        LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: snapshot.createdAt,
            asOf: Date(),
            using: viewContext,
            calendar: calendar
        )
    }

    // Maps age thresholds to the shared PresentationStatus ramp.
    // Thresholds are unchanged: >21 days = overdue, >14 days = brewing.
    private enum Priority {
        case low, medium, high

        var stripColor: Color {
            switch self {
            case .low:    return Color.gray.opacity(0.18)
            case .medium: return AppColors.color(for: .brewing)
            case .high:   return AppColors.color(for: .overdue)
            }
        }
    }

    private var priority: Priority {
        let age = ageInSchoolDays
        if age > 21 { return .high }
        if age > 14 { return .medium }
        return .low
    }

    private var absentStudentIDs: Set<UUID> {
        Set(attendanceCache.filter { $0.value == .absent }.keys)
    }

    private var hasAbsentStudent: Bool { !absentStudentIDs.isEmpty }

    private var hasDoubleBookedStudent: Bool {
        snapshot.studentIDs.contains { doubleBookedStudentIDs.contains($0) }
    }

    private var isOverdue: Bool { priority != .low }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(priority.stripColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                titleRow
                studentChipsRow
                readinessFooter
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            statusIcons
                .padding(.trailing, AppTheme.Spacing.compact)
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .task { loadAttendanceIfNeeded() }
        .onChange(of: day) { _, _ in loadAttendanceIfNeeded(force: true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var titleRow: some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            Circle()
                .fill(areaColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(lessonName)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            periodBadge
        }
    }

    /// A scheduled presentation has no time, so AM/PM is the whole of what the
    /// card can say about when — kept monochrome deliberately: the card already
    /// spends colour on the subject area, the age strip and the two warnings,
    /// and a fourth colour language would make none of them read.
    @ViewBuilder
    private var periodBadge: some View {
        if let period {
            Text(period.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, UIConstants.CardSize.statusPillHorizontal)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                )
                .accessibilityLabel(period.label)
        }
    }

    private var studentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.xxsmall) {
                ForEach(snapshot.studentIDs, id: \.self) { sid in
                    if let student = students.first(where: { $0.id == sid }) {
                        studentChip(for: student, sid: sid)
                    }
                }
            }
        }
    }

    private func studentChip(for student: CDStudent, sid: UUID) -> some View {
        let name = StudentFormatter.displayName(for: student)
        let isAbsent = attendanceCache[sid] == .absent
        let isDoubleBooked = doubleBookedStudentIDs.contains(sid)
        let isBlocking = blockingWork[sid] != nil
        let indicator: Color? = {
            if isAbsent { return .red }
            if isDoubleBooked { return AppColors.attention }
            if isBlocking { return AppColors.color(for: .brewing) }
            return nil
        }()

        return Text(name)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(isAbsent ? .secondary : .primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            )
            .overlay(
                Capsule()
                    .stroke(indicator ?? .clear, lineWidth: indicator == nil ? 0 : 1.5)
            )
    }

    // MARK: - Readiness footer

    @ViewBuilder
    private var readinessFooter: some View {
        if let ready = readyCount, let total = totalCount, total > 1 {
            let footerColor = ready == total
                ? AppColors.color(for: .ready)
                : AppColors.color(for: .brewing)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                // Thin progress bar
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(footerColor)
                                .frame(
                                    width: max(0, geo.size.width * Double(ready) / Double(total)),
                                    height: 3
                                )
                        }
                        .frame(height: 3)
                    }

                Text("\(ready) of \(total) ready")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ready > 0 ? footerColor : .secondary)
            }
            .padding(.top, AppTheme.Spacing.xxsmall)
        }
    }

    @ViewBuilder
    private var statusIcons: some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            if hasAbsentStudent {
                Image(systemName: "person.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Student absent")
            }
            if hasDoubleBookedStudent {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(AppColors.attention)
                    .accessibilityLabel("Two lessons in the same half of the day")
            }
            if isOverdue {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(priority.stripColor)
                    .accessibilityLabel("Overdue")
            }
        }
    }

    // MARK: - Background

    private var cardBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.secondarySystemGroupedBackground)
        #endif
    }

    private var borderColor: Color {
        Color.gray.opacity(0.12)
    }

    private var accessibilityLabel: String {
        let names = snapshot.studentIDs.compactMap { sid -> String? in
            guard let student = students.first(where: { $0.id == sid }) else { return nil }
            return StudentFormatter.displayName(for: student)
        }.joined(separator: ", ")
        // The card combines its children, so the badge's own label is replaced
        // by this one — the half has to be spoken here or not at all.
        return [lessonName, names, period?.label]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    // MARK: - Attendance fetch

    private func loadAttendanceIfNeeded(force: Bool = false) {
        guard let day else {
            attendanceCache = [:]
            lastAttendanceDay = nil
            return
        }
        let normalized = calendar.startOfDay(for: day)
        if !force, lastAttendanceDay == normalized { return }
        let ids = Array(snapshot.studentIDs)
        let statuses = viewContext.attendanceStatuses(for: ids, on: normalized)
        attendanceCache = statuses
        lastAttendanceDay = normalized
    }
}
