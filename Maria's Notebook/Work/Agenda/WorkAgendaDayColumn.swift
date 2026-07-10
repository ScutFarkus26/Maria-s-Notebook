import SwiftUI
import CoreData

/// A day column for the Work agenda calendar that displays both work items and lesson assignments
struct WorkAgendaDayColumn: View {
    @Environment(\.managedObjectContext) private var modelContext

    let day: Date
    let availableHeight: CGFloat
    let showPresentations: Bool
    let onPillTap: (CDWorkCheckIn) -> Void
    let onSequenceTap: ((CheckInGroup) -> Void)?
    let onLessonAssignmentSelect: ((CDLessonAssignment) -> Void)?

    // Fetch work check-ins for this day (scheduled status only)
    @FetchRequest private var allCheckIns: FetchedResults<CDWorkCheckIn>

    // Fetch scheduled lesson assignments (not yet presented)
    @FetchRequest private var allLessonAssignments: FetchedResults<CDLessonAssignment>

    init(
        day: Date,
        availableHeight: CGFloat,
        showPresentations: Bool = true,
        onPillTap: @escaping (CDWorkCheckIn) -> Void,
        onSequenceTap: ((CheckInGroup) -> Void)? = nil,
        onLessonAssignmentSelect: ((CDLessonAssignment) -> Void)? = nil
    ) {
        self.day = day
        self.availableHeight = availableHeight
        self.showPresentations = showPresentations
        self.onPillTap = onPillTap
        self.onSequenceTap = onSequenceTap
        self.onLessonAssignmentSelect = onLessonAssignmentSelect

        // Initialize work check-ins query for this day (scheduled status only)
        let (start, end) = AppCalendar.dayRange(for: day)
        _allCheckIns = FetchRequest(
            sortDescriptors: [],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "statusRaw == %@", "Scheduled"),
                NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
            ])
        )
        _allLessonAssignments = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "stateRaw != %@", "presented")
        )
    }

    private var lessonAssignmentsForDay: [CDLessonAssignment] {
        let (start, end) = AppCalendar.dayRange(for: day)
        return allLessonAssignments.filter { la in
            guard let scheduledDate = la.scheduledFor else { return false }
            return scheduledDate >= start && scheduledDate < end
        }
    }

    // MARK: - Check-in Grouping

    /// A resolved check-in sequence: one or more check-ins sharing the same lesson and purpose
    struct CheckInGroup: Identifiable {
        let id: UUID
        /// All check-ins in this sequence (same lesson + purpose)
        let checkIns: [CDWorkCheckIn]
        let lessonTitle: String
        let studentNames: [String]
        let purpose: String
        let sortDate: Date

        /// Representative check-in (first) for actions like drag/tap
        var primary: CDWorkCheckIn { checkIns[0] }
        var isGrouped: Bool { checkIns.count > 1 }
    }

    /// Resolves lesson title for a work's lessonID
    private func resolvedLessonTitle(for work: CDWorkModel) -> String {
        if let lessonID = work.lessonID.asUUID {
            let request = CDFetchRequest(CDLesson.self)
            request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
            if let lesson = modelContext.safeFetchFirst(request) {
                let name = lesson.name.trimmed()
                if !name.isEmpty { return name }
            }
        }
        return "Lesson \(String(work.lessonID.prefix(6)))"
    }

    /// Resolves display name for a work's studentID
    private func resolvedStudentName(for work: CDWorkModel) -> String {
        if let studentID = work.studentID.asUUID {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
            if let student = modelContext.safeFetchFirst(request) {
                return StudentFormatter.displayName(for: student)
            }
        }
        return ""
    }

    /// Groups check-ins that share the same lessonID and purpose into merged pills.
    /// Respects the work's checkInStyle: individual items are never grouped.
    private var groupedCheckIns: [CheckInGroup] {
        // Resolve work for each check-in, skip any that can't be resolved
        struct Resolved {
            let checkIn: CDWorkCheckIn
            let work: CDWorkModel
            let lessonTitle: String
            let studentName: String
            let sequenceKey: String  // lessonID + purpose
            let checkInStyle: CheckInStyle
        }

        var resolved: [Resolved] = []
        for ci in allCheckIns {
            guard let workID = ci.workID.asUUID else { continue }
            let workRequest = CDFetchRequest(CDWorkModel.self)
            workRequest.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
            guard let work = modelContext.safeFetchFirst(workRequest) else { continue }
            let lessonTitle = resolvedLessonTitle(for: work)
            let studentName = resolvedStudentName(for: work)
            let sequenceKey = "\(work.lessonID)|\(ci.purpose)"
            resolved.append(Resolved(
                checkIn: ci, work: work,
                lessonTitle: lessonTitle,
                studentName: studentName,
                sequenceKey: sequenceKey,
                checkInStyle: work.checkInStyle
            ))
        }

        // Separate individual-style items from groupable items
        var individualItems: [Resolved] = []
        var groupableItems: [Resolved] = []
        for r in resolved {
            if r.checkInStyle == .individual {
                individualItems.append(r)
            } else {
                groupableItems.append(r)
            }
        }

        // Group groupable items by lessonID + purpose, preserving first-appearance order
        var order: [String] = []
        var buckets: [String: [Resolved]] = [:]
        for r in groupableItems {
            if buckets[r.sequenceKey] == nil { order.append(r.sequenceKey) }
            buckets[r.sequenceKey, default: []].append(r)
        }

        var result: [CheckInGroup] = []

        // Emit grouped items
        for key in order {
            guard let items = buckets[key], !items.isEmpty else { continue }
            let checkIns = items.map(\.checkIn)
            let studentNames = items.map(\.studentName).filter { !$0.isEmpty }
            result.append(CheckInGroup(
                id: items[0].checkIn.id ?? UUID(),
                checkIns: checkIns,
                lessonTitle: items[0].lessonTitle,
                studentNames: studentNames,
                purpose: items[0].checkIn.purpose,
                sortDate: items[0].checkIn.date ?? Date()
            ))
        }

        // Emit individual items as single-item groups
        for r in individualItems {
            result.append(CheckInGroup(
                id: r.checkIn.id ?? UUID(),
                checkIns: [r.checkIn],
                lessonTitle: r.lessonTitle,
                studentNames: r.studentName.isEmpty ? [] : [r.studentName],
                purpose: r.checkIn.purpose,
                sortDate: r.checkIn.date ?? Date()
            ))
        }

        return result
    }

    private enum CalendarItem: Identifiable {
        case checkInGroup(CheckInGroup)
        case lessonAssignment(CDLessonAssignment)

        var id: UUID {
            switch self {
            case .checkInGroup(let g): return g.id
            case .lessonAssignment(let la): return la.id ?? UUID()
            }
        }

        var sortDate: Date {
            switch self {
            case .checkInGroup(let g): return g.sortDate
            case .lessonAssignment(let la): return la.scheduledFor ?? .distantPast
            }
        }
    }

    private var allItems: [CalendarItem] {
        let work = groupedCheckIns.map { CalendarItem.checkInGroup($0) }
        let lessons = showPresentations ? lessonAssignmentsForDay.map { CalendarItem.lessonAssignment($0) } : []
        return (work + lessons).sorted { $0.sortDate < $1.sortDate }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(Date.FormatStyle().weekday(.abbreviated).day()))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(allItems) { item in
                    switch item {
                    case .checkInGroup(let sequence):
                        if sequence.isGrouped {
                            GroupedWorkCheckInPill(sequence: sequence) {
                                if let onSequenceTap { onSequenceTap(sequence) } else { onPillTap(sequence.primary) }
                            }
                            .draggable(
                                UnifiedCalendarDragPayload.workCheckIn(sequence.primary.id ?? UUID())
                                    .stringRepresentation
                            ) {
                                GroupedWorkCheckInPill(sequence: sequence)
                                    .opacity(UIConstants.OpacityConstants.almostOpaque)
                            }
                        } else {
                            WorkCheckInPill(checkIn: sequence.primary, isDulled: false) {
                                onPillTap(sequence.primary)
                            }
                            .draggable(
                                UnifiedCalendarDragPayload.workCheckIn(sequence.primary.id ?? UUID())
                                    .stringRepresentation
                            ) {
                                WorkCheckInPill(checkIn: sequence.primary, isDulled: false)
                                    .opacity(UIConstants.OpacityConstants.almostOpaque)
                            }
                        }
                    case .lessonAssignment(let la):
                        PresentationPill(
                            snapshot: la.snapshot(),
                            day: day,
                            targetLessonAssignmentID: la.id,
                            showTimeBadge: false,
                            enableMergeDrop: false,
                            showAgeIndicator: false
                        )
                        .opacity(UIConstants.OpacityConstants.half)
                        .draggable(UnifiedCalendarDragPayload.presentation(la.id ?? UUID()).stringRepresentation) {
                            PresentationPill(
                                snapshot: la.snapshot(),
                                day: day,
                                targetLessonAssignmentID: la.id,
                                showTimeBadge: false,
                                enableMergeDrop: false,
                                showAgeIndicator: false
                            )
                            .opacity(0.45)
                        }
                        .onTapGesture {
                            onLessonAssignmentSelect?(la)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.small)
            .frame(
                minWidth: 260, idealWidth: 260, maxWidth: 260,
                minHeight: 0, idealHeight: .infinity,
                maxHeight: .infinity, alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .stroke(
                        Color.primary.opacity(UIConstants.OpacityConstants.faint),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
            )
        }
        .frame(height: availableHeight, alignment: .topLeading)
    }
}

// MARK: - Grouped Pill

/// A pill that consolidates multiple check-ins for the same lesson and purpose into one row
struct GroupedWorkCheckInPill: View {
    let sequence: WorkAgendaDayColumn.CheckInGroup
    var onTap: (() -> Void)?

    private var purposeIcon: String {
        let purpose = sequence.purpose.lowercased()
        if purpose.contains("progress") || purpose.contains("check") {
            return "checkmark.circle"
        } else if purpose.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if purpose.contains("assessment") {
            return "chart.bar"
        } else if purpose.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }

    private var studentNamesDisplay: String {
        sequence.studentNames.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // CDStudent count badge
                Text("\(sequence.checkIns.count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                Text(sequence.lessonTitle)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(studentNamesDisplay)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !sequence.purpose.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: purposeIcon)
                        .foregroundStyle(.secondary)
                    Text(sequence.purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.faint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(
                    Color.accentColor.opacity(UIConstants.OpacityConstants.light),
                    lineWidth: UIConstants.StrokeWidth.thin
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}
