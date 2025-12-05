import SwiftUI
import SwiftData
import UniformTypeIdentifiers

fileprivate struct InboxPillFramePreference: PreferenceKey {
  static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

public struct InboxSheetView: View {
  let studentLessons: [StudentLesson]
  let orderedUnscheduledLessons: [StudentLesson]
  @Binding var inboxOrderRaw: String

  let onOpenDetails: (UUID) -> Void
  let onQuickActions: (UUID) -> Void
  let onPlanNext: (StudentLesson) -> Void
  let onUpdateOrder: ((String) -> Void)?

  @Environment(\.calendar) private var calendar
  @Environment(\.modelContext) private var modelContext
  @State private var selected: Set<UUID> = []

  @State private var itemFrames: [UUID: CGRect] = [:]
  @State private var spaceID = UUID()
  @State private var isTargeted = false

  private static let mediumDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df
  }()
  
  private static let weekdayFormatter: DateFormatter = {
    let df = DateFormatter()
    df.setLocalizedDateFormatFromTemplate("EEE")
    return df
  }()

  init(
    studentLessons: [StudentLesson],
    orderedUnscheduledLessons: [StudentLesson],
    inboxOrderRaw: Binding<String>,
    onOpenDetails: @escaping (UUID) -> Void,
    onQuickActions: @escaping (UUID) -> Void,
    onPlanNext: @escaping (StudentLesson) -> Void,
    onUpdateOrder: ((String) -> Void)? = nil
  ) {
    self.studentLessons = studentLessons
    self.orderedUnscheduledLessons = orderedUnscheduledLessons
    self._inboxOrderRaw = inboxOrderRaw
    self.onOpenDetails = onOpenDetails
    self.onQuickActions = onQuickActions
    self.onPlanNext = onPlanNext
    self.onUpdateOrder = onUpdateOrder
  }

  private func monday(for date: Date) -> Date {
    let start = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: start)
    let daysToSubtract = (weekday + 5) % 7
    return calendar.date(byAdding: .day, value: -daysToSubtract, to: start) ?? start
  }

  private func scheduleSelected(to day: Date, hour: Int) {
    let idsInOrder: [UUID] = orderedUnscheduledLessons.map { $0.id }.filter { selected.contains($0) }
    guard !idsInOrder.isEmpty else { return }
    let base = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: day)) ?? day
    let timeMap = PlanningDropUtils.assignSequentialTimes(ids: idsInOrder, base: base, calendar: calendar, spacingSeconds: 60)
    for id in idsInOrder {
      if let sl = studentLessons.first(where: { $0.id == id }) {
        sl.scheduledFor = timeMap[id]
      }
    }
    selected.removeAll()
    Task { @MainActor in try? modelContext.save() }
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "tray")
          .imageScale(.large)
          .frame(width: 24, height: 24)
          .foregroundColor(.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("📥 Inbox")
            .font(.headline)
            .foregroundColor(.primary)
          Text("Unscheduled lessons")
            .font(.callout)
            .foregroundColor(.secondary)
        }
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      if orderedUnscheduledLessons.isEmpty {
        VStack {
          Spacer()
          Text("No unscheduled lessons")
            .font(.callout)
            .foregroundColor(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        // Batch actions bar
        let start = monday(for: Date())
        let days: [Date] = (0..<5).compactMap { offset in
          calendar.date(byAdding: .day, value: offset, to: start)
        }
        HStack(spacing: 8) {
          Menu {
            ForEach(days, id: \.self) { day in
              let wd = Self.weekdayFormatter.string(from: day)
              let baseLabel = Self.mediumDateFormatter.string(from: day)
              let isNS = SchoolCalendar.isNonSchoolDay(day, using: modelContext)
              Button("\(wd), \(baseLabel) — Morning") {
                scheduleSelected(to: day, hour: 9)
              }
              .disabled(isNS)
              Button("\(wd), \(baseLabel) — Afternoon") {
                scheduleSelected(to: day, hour: 14)
              }
              .disabled(isNS)
            }
          } label: {
            Label("Schedule Selected", systemImage: "calendar.badge.plus")
          }
          .disabled(selected.isEmpty)

          if !selected.isEmpty {
            Text("\(selected.count) selected")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        ScrollView {
          VStack(spacing: 10) {
            ForEach(orderedUnscheduledLessons, id: \.id) { sl in
              InboxRow(
                sl: sl,
                isSelected: selected.contains(sl.id),
                isSelectionMode: !selected.isEmpty,
                spaceID: spaceID,
                onToggleSelected: {
                  if selected.contains(sl.id) { selected.remove(sl.id) } else { selected.insert(sl.id) }
                },
                onOpenDetails: onOpenDetails,
                onQuickActions: onQuickActions,
                onPlanNext: onPlanNext
              )
            }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
        }
        .coordinateSpace(name: spaceID)
        .onPreferenceChange(InboxPillFramePreference.self) { prefs in
          itemFrames = prefs
        }
        .onDrop(
          of: [UTType.text],
          isTargeted: $isTargeted,
          perform: handleDrop(providers:location:)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(isTargeted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
        )
      }
    }
  }

  private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
    guard let itemProvider = providers.first else { return false }
    if itemProvider.canLoadObject(ofClass: NSString.self) {
      _ = itemProvider.loadObject(ofClass: NSString.self) { reading, _ in
        guard let ns = reading as? NSString else { return }
        let uuidString = ns as String
        guard let droppedId = UUID(uuidString: uuidString) else { return }
        DispatchQueue.main.async {
          dropReceived(droppedId: droppedId, location: location)
        }
      }
      return true
    }
    return false
  }

  private func dropReceived(droppedId: UUID, location: CGPoint) {
    guard let sl = studentLessons.first(where: { $0.id == droppedId }) else { return }
    let currentOrder = orderedUnscheduledLessons.map(\.id)
    var framesByID: [UUID: CGRect] = [:]
    for id in currentOrder {
      if let frame = itemFrames[id] {
        framesByID[id] = frame
      }
    }
    let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
    var newOrder = currentOrder
    // Filter to only unscheduled lessons in current order
    newOrder = newOrder.filter { currentOrder.contains($0) }
    // If scheduled, clear scheduledFor
    if sl.scheduledFor != nil {
      let targetId = droppedId
      let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetId })
      if let lesson = try? modelContext.fetch(descriptor).first {
        lesson.scheduledFor = nil
        try? modelContext.save()
      }
    }
    // Remove existing occurrence
    newOrder.removeAll(where: { $0 == droppedId })
    // Insert at bounded index
    let boundedIndex = max(0, min(insertionIndex, newOrder.count))
    newOrder.insert(droppedId, at: boundedIndex)
    // Serialize and update
    let serialized = InboxOrderStore.serialize(newOrder)
    inboxOrderRaw = serialized
    onUpdateOrder?(serialized)
    try? modelContext.save()
  }
}

fileprivate struct InboxRow: View {
  let sl: StudentLesson
  let isSelected: Bool
  let isSelectionMode: Bool
  let spaceID: UUID
  let onToggleSelected: () -> Void
  let onOpenDetails: (UUID) -> Void
  let onQuickActions: (UUID) -> Void
  let onPlanNext: (StudentLesson) -> Void
  var body: some View {
    HStack(spacing: 8) {
      Button(action: onToggleSelected) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.plain)

      StudentLessonPill(snapshot: sl.snapshot(), day: Date())
        .onTapGesture {
          if isSelectionMode {
            onToggleSelected()
          } else {
            onOpenDetails(sl.id)
          }
        }
        .onDrag {
          NSItemProvider(object: NSString(string: sl.id.uuidString))
        }
        .contextMenu {
          Button { onQuickActions(sl.id) } label: { Label("Quick Actions…", systemImage: "bolt") }
          Button { onPlanNext(sl) } label: { Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus") }
          Button { onOpenDetails(sl.id) } label: { Label("Open Details", systemImage: "info.circle") }
        }
    }
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    )
    .contentShape(Rectangle())
    .background(
      GeometryReader { proxy in
        Color.clear
          .preference(
            key: InboxPillFramePreference.self,
            value: [sl.id: proxy.frame(in: .named(spaceID))]
          )
      }
    )
  }
}

