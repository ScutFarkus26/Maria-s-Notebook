import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct AgendaSlot: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar

    let allLessonAssignments: [CDLessonAssignment]
    let day: Date
    let period: DayPeriod
    let onSelectLesson: (CDLessonAssignment) -> Void
    let onQuickActions: (CDLessonAssignment) -> Void
    let onPlanNext: (CDLessonAssignment) -> Void
    let onMoveToInbox: (CDLessonAssignment) -> Void
    let onMoveStudents: (CDLessonAssignment) -> Void

    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var zoneSpaceID = UUID()
    @State private var isTargeted: Bool = false
    @State private var insertionIndex: Int?

    private var scheduledLessonsForSlot: [CDLessonAssignment] {
        allLessonAssignments.filter { la in
            guard let scheduled = la.scheduledFor, !la.isGiven else { return false }
            return calendar.isDate(scheduled, inSameDayAs: day) && isInSlot(scheduled, period: period)
        }
        .sorted { ($0.scheduledFor ?? .distantPast) < ($1.scheduledFor ?? .distantPast) }
    }

    init(
        allLessonAssignments: [CDLessonAssignment],
        day: Date,
        period: DayPeriod,
        onSelectLesson: @escaping (CDLessonAssignment) -> Void,
        onQuickActions: @escaping (CDLessonAssignment) -> Void,
        onPlanNext: @escaping (CDLessonAssignment) -> Void,
        onMoveToInbox: @escaping (CDLessonAssignment) -> Void,
        onMoveStudents: @escaping (CDLessonAssignment) -> Void
    ) {
        self.allLessonAssignments = allLessonAssignments
        self.day = day
        self.period = period
        self.onSelectLesson = onSelectLesson
        self.onQuickActions = onQuickActions
        self.onPlanNext = onPlanNext
        self.onMoveToInbox = onMoveToInbox
        self.onMoveStudents = onMoveStudents
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.04 : 0.02))

            if isTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.prominent), lineWidth: 3)
                    .allowsHitTesting(false)
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
            .padding(12)
            .overlay(
                GeometryReader { proxy in
                    if let idx = insertionIndex {
                        let frames: [(UUID, CGRect)] = scheduledLessonsForSlot.compactMap { item in
                            guard let id = item.id, let rect = itemFrames[id] else { return nil }
                            return (id, rect)
                        }.sorted { $0.1.minY < $1.1.minY }

                        if frames.isEmpty {
                            // Empty slot - show indicator at top
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width - 24, height: 3)
                                .position(x: proxy.size.width / 2, y: 12)
                        } else {
                            // Show indicator at insertion position
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
            // Defer state update to next run loop to avoid layout recursion
            // PreferenceKey updates happen during layout, so we must defer state changes
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
            baseDateProvider: { AgendaSlot.baseDateForSlot(day: day, period: period, calendar: calendar) },
            spacingSeconds: 1,
            getCurrent: { scheduledLessonsForSlot },
            itemFramesProvider: { itemFrames },
            onTargetChange: { targeted in
                isTargeted = targeted
            },
            onInsertionIndexChange: { idx in
                insertionIndex = idx
            }
        ))
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func lessonPillView(for la: CDLessonAssignment) -> some View {
        PresentationPill(
            snapshot: la.snapshot(),
            day: day,
            sourceLessonAssignmentID: la.id,
            targetLessonAssignmentID: la.id,
            enableMergeDrop: true
        )
        .draggable(la.id?.uuidString ?? "") {
            // Custom drag preview
            PresentationPill(
                snapshot: la.snapshot(),
                day: day,
                sourceLessonAssignmentID: la.id,
                targetLessonAssignmentID: la.id
            )
            .opacity(UIConstants.OpacityConstants.heavy)
        }
        .onTapGesture {
            onSelectLesson(la)
        }
        .contextMenu {
            Button {
                onQuickActions(la)
            } label: {
                Label("Quick Actions…", systemImage: "bolt")
            }

            Button {
                onPlanNext(la)
            } label: {
                Label("Plan Next Lesson in Group", systemImage: SFSymbol.Time.calendarBadgePlus)
            }

            Button {
                onSelectLesson(la)
            } label: {
                Label("Open Details", systemImage: SFSymbol.Status.infoCircle)
            }

            Button {
                onMoveStudents(la)
            } label: {
                Label("Move Students…", systemImage: "person.2.arrow.right")
            }

            Button {
                onMoveToInbox(la)
            } label: {
                Label("Move to Inbox", systemImage: SFSymbol.CDDocument.tray)
            }
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

    private func isInSlot(_ date: Date, period: DayPeriod) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch period {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12
        }
    }

    @MainActor static func baseDateForSlot(day: Date, period: DayPeriod, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        let hour: Int = (period == .morning) ? 9 : 14
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
    }
}

struct PillFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
