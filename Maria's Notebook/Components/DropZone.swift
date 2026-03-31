import OSLog
import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct DropZone: View {
    private static let logger = Logger.lessons
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    let allLessonAssignments: [CDLessonAssignment]

    // Visual/drag state
    @State private var isTargeted: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var insertionIndex: Int?

    // Inputs
    let day: Date
    let period: PlanningDayPeriod
    let onSelectLesson: (CDLessonAssignment) -> Void
    let onQuickActions: (CDLessonAssignment) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void

    /// Synchronous helper that determines if a date is a non-school day using direct NSManagedObjectContext fetches.
    private func isNonSchoolDaySync(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins
        do {
            var nsDescriptor = { let r = CDNonSchoolDay.fetchRequest() as! NSFetchRequest<CDNonSchoolDay>; r.predicate = NSPredicate(format: "date == %@", day as CVarArg); return r }()
            nsDescriptor.fetchLimit = 1
            let nonSchoolDays: [CDNonSchoolDay] = try viewContext.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            Self.logger.error("[\(#function)] Failed to fetch non-school days: \(error)")
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            var ovDescriptor = { let r = CDSchoolDayOverride.fetchRequest() as! NSFetchRequest<CDSchoolDayOverride>; r.predicate = NSPredicate(format: "date == %@", day as CVarArg); return r }()
            ovDescriptor.fetchLimit = 1
            let overrides: [CDSchoolDayOverride] = try viewContext.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            Self.logger.error("[\(#function)] Failed to fetch school day overrides: \(error)")
        }
        return true
    }

    private var isNonSchool: Bool { isNonSchoolDaySync(day) }

    private var scheduledLessonsForSlot: [CDLessonAssignment] {
        allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Minimal card background matching the rest of the app
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.04 : 0.02))

            // Accent outline when targeted
            if isTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.prominent), lineWidth: 3)
                    .allowsHitTesting(false)
            }

            // Non-school overlay
            if isNonSchool {
                Text("No School")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                if scheduledLessonsForSlot.isEmpty {
                    Text("No plans yet")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(Array(scheduledLessonsForSlot.enumerated()), id: \.element.id) { _, la in
                        lessonPillView(for: la)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 22, leading: 12, bottom: 12, trailing: 12))
            .overlay(
                // Insertion indicator line, similar to Agenda view
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = scheduledLessonsForSlot.compactMap { item in
                            guard let itemID = item.id, let rect = itemFrames[itemID] else { return nil }
                            return (itemID, rect)
                        }.sorted { $0.1.minY < $1.1.minY }

                        if frames.isEmpty {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: 12)
                        } else {
                            let y: CGFloat = {
                                if idx < frames.count {
                                    return frames[idx].1.minY
                                } else if let lastFrame = frames.last {
                                    return lastFrame.1.maxY + 8
                                } else {
                                    return 12
                                }
                            }()
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: y)
                        }
                    }
                }
            )
        }
        .coordinateSpace(name: zoneSpaceID)
        .onPreferenceChange(PillFramePreference.self) { frames in
            Task { @MainActor in
                itemFrames = frames
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrop(of: [UTType.text], delegate: PlanningSlotDropDelegate(
            calendar: calendar,
            viewContext: viewContext,
            allLessonAssignments: allLessonAssignments,
            day: day,
            baseDateProvider: { dateForSlot(day: day, period: period) },
            spacingSeconds: UIConstants.scheduleSpacingSeconds,
            getCurrent: { scheduledLessonsForSlot },
            itemFramesProvider: { itemFrames },
            onTargetChange: { targeted in
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { isTargeted = targeted }
            },
            onInsertionIndexChange: { idx in
                if insertionIndex != idx {
                    adaptiveWithAnimation(
                        .interactiveSpring(response: 0.16, dampingFraction: 0.85)
                    ) { insertionIndex = idx }
                }
            }
        ))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isNonSchool)
    }

    @ViewBuilder
    private func lessonPillView(for la: CDLessonAssignment) -> some View {
        PresentationPill(
            snapshot: la.snapshot(),
            day: day,
            sourceLessonAssignmentID: la.id,
            targetLessonAssignmentID: la.id,
            enableMergeDrop: true
        )
        .draggable((la.id ?? UUID()).uuidString) {
            PresentationPill(
                snapshot: la.snapshot(),
                day: day,
                sourceLessonAssignmentID: la.id,
                targetLessonAssignmentID: la.id
            )
            .opacity(UIConstants.OpacityConstants.nearSolid)
        }
        .onTapGesture { onSelectLesson(la) }
        .contextMenu {
            Button { onQuickActions(la) } label: { Label("Quick Actions…", systemImage: "bolt") }
            Button { onPlanNext(la) } label: {
                Label("Plan Next CDLesson in Group", systemImage: SFSymbol.Time.calendarBadgePlus)
            }
            Button { onSelectLesson(la) } label: { Label("Open Details", systemImage: SFSymbol.Status.infoCircle) }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PillFramePreference.self,
                    value: la.id.map { [$0: proxy.frame(in: .named(zoneSpaceID))] } ?? [:]
                )
            }
        )
    }

    private func isInSlot(_ date: Date, period: PlanningDayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12
        }
    }

    private func dateForSlot(day: Date, period: PlanningDayPeriod) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int
        switch period {
        case .morning: hour = UIConstants.morningHour
        case .afternoon: hour = UIConstants.afternoonHour
        }
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }

    private struct PillFramePreference: PreferenceKey {
        nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }
}
