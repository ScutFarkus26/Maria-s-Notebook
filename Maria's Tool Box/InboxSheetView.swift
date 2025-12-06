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
  @State private var insertionIndex: Int? = nil
  @State private var baseFrames: [UUID: CGRect]? = nil
  @State private var toastMessage: String? = nil

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

  private func consolidateSelected() {
    // Gather selected unscheduled lessons
    let selectedSLs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
    guard !selectedSLs.isEmpty else { return }

    // Group by lesson ID
    let groups = Dictionary(grouping: selectedSLs, by: { $0.lessonID })
    var consolidatedGroups = 0
    var totalMerged = 0

    // Keep track of which IDs will be deleted to update order
    var deletedIDs: [UUID] = []
    let currentOrder = orderedUnscheduledLessons.map(\.id)

    for (_, group) in groups {
      guard group.count >= 2 else { continue }
      consolidatedGroups += 1
      totalMerged += (group.count - 1)

      // Choose a target: the first occurrence in current order among this group's items
      let groupIDs = group.map(\.id)
      guard let targetID = currentOrder.first(where: { groupIDs.contains($0) }),
            let target = studentLessons.first(where: { $0.id == targetID }) else { continue }

      // Union of student IDs across the group
      var union = Set<UUID>(target.studentIDs)
      for sl in group { union.formUnion(sl.studentIDs) }
      let remainingIDs = Array(union)

      // Update target's students
      target.studentIDs = remainingIDs
      let fetch = FetchDescriptor<Student>(predicate: #Predicate { remainingIDs.contains($0.id) })
      let fetched = (try? modelContext.fetch(fetch)) ?? []
      target.students = fetched
      target.syncSnapshotsFromRelationships()

      // Delete the others in the group
      for sl in group where sl.id != targetID {
        deletedIDs.append(sl.id)
        modelContext.delete(sl)
      }
    }

    // Persist changes
    try? modelContext.save()

    // Update inbox order by removing deleted IDs
    var newOrder = currentOrder
    for id in deletedIDs { newOrder.removeAll { $0 == id } }
    let serialized = InboxOrderStore.serialize(newOrder)
    inboxOrderRaw = serialized
    onUpdateOrder?(serialized)

    let msg: String = consolidatedGroups == 1 ? "Consolidated 1 lesson" : "Consolidated \(consolidatedGroups) lessons"
    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
      toastMessage = msg
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      withAnimation(.easeInOut(duration: 0.25)) { toastMessage = nil }
    }

    // Clear selection and notify any listeners to refresh
    selected.removeAll()
    NotificationCenter.default.post(name: Notification.Name("PlanningInboxNeedsRefresh"), object: nil)
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
        let canConsolidate: Bool = {
          let selectedSLs = orderedUnscheduledLessons.filter { selected.contains($0.id) }
          let groups = Dictionary(grouping: selectedSLs, by: { $0.lessonID })
          return groups.values.contains { $0.count >= 2 }
        }()
        HStack(spacing: 8) {
          Button {
            consolidateSelected()
          } label: {
            Label("Consolidate Selected", systemImage: "arrow.triangle.merge")
          }
          .disabled(!canConsolidate)

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
            ForEach(Array(orderedUnscheduledLessons.enumerated()), id: \.element.id) { index, sl in
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
              // Removed offset to reduce layout churn
            }
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
        }
        .coordinateSpace(name: spaceID)
        .onPreferenceChange(InboxPillFramePreference.self) { prefs in
          itemFrames = prefs
        }
        .onDrop(of: [UTType.text], delegate: InboxDropDelegate(
          getCurrent: { orderedUnscheduledLessons },
          itemFramesProvider: { baseFrames ?? itemFrames },
          onTargetChange: { targeted in
            withAnimation(.easeInOut(duration: 0.1)) { isTargeted = targeted }
            if targeted {
              if baseFrames == nil { baseFrames = itemFrames }
            } else {
              baseFrames = nil
            }
          },
          onInsertionIndexChange: { idx in
            if idx != insertionIndex {
              withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.85)) { insertionIndex = idx }
            }
          },
          performDropHandler: { providers, location in
            handleDrop(providers: providers, location: location)
          }
        ))
        .overlay(
          GeometryReader { proxy in
            let placeholderWidth = max(0, proxy.size.width - 24) // content has 12pt horizontal padding on each side
            let placeholderHeight: CGFloat = 44

            Group {
              if let idx = insertionIndex {
                let frames: [(UUID, CGRect)] = orderedUnscheduledLessons.compactMap { item in
                  if let rect = (baseFrames ?? itemFrames)[item.id] { return (item.id, rect) }
                  return nil
                }.sorted { $0.1.minY < $1.1.minY }

                if frames.isEmpty {
                  // Empty list case: show placeholder near the top padding
                  let yTop = 10 + placeholderHeight / 2
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                    .frame(width: placeholderWidth, height: placeholderHeight)
                    .position(x: proxy.size.width / 2, y: yTop)
                    .transition(.opacity.combined(with: .scale))
                } else {
                  let y: CGFloat = (idx < frames.count) ? frames[idx].1.minY : (frames.last!.1.maxY)
                  let placeholderY = y + placeholderHeight / 2

                  // Spacer behind placeholder to reserve vertical space
                  Color.clear
                    .frame(width: placeholderWidth, height: placeholderHeight)
                    .position(x: proxy.size.width / 2, y: placeholderY)
                    .allowsHitTesting(false)

                  // Ghost placeholder
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                    .frame(width: placeholderWidth, height: placeholderHeight)
                    .position(x: proxy.size.width / 2, y: placeholderY)
                    .transition(.opacity.combined(with: .scale))

                  // Accent insertion line
                  Capsule()
                    .fill(Color.accentColor)
                    .frame(width: placeholderWidth, height: 3)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4)
                    .position(x: proxy.size.width / 2, y: y)
                }
              } else if isTargeted && orderedUnscheduledLessons.isEmpty {
                // No insertion index yet, but we are targeted and empty: hint at top
                let yTop = 10 + placeholderHeight / 2
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(Color.accentColor.opacity(0.08))
                  .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                      .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                  )
                  .frame(width: placeholderWidth, height: placeholderHeight)
                  .position(x: proxy.size.width / 2, y: yTop)
                  .transition(.opacity.combined(with: .scale))
              }
            }
          }
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(isTargeted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
      }
    }
    .overlay(alignment: .top) {
      if let message = toastMessage {
        Text(message)
          .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color.black.opacity(0.85))
          )
          .foregroundColor(.white)
          .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
          .transition(.move(edge: .top).combined(with: .opacity))
          .padding(.top, 8)
      }
    }
  }

  private func handleDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
    guard let itemProvider = providers.first else { return false }
    if itemProvider.canLoadObject(ofClass: NSString.self) {
      _ = itemProvider.loadObject(ofClass: NSString.self) { reading, _ in
        guard let ns = reading as? NSString else { return }
        let raw = ns as String
        if raw.hasPrefix("STUDENT_TO_INBOX:") {
          DispatchQueue.main.async {
            handleStudentToInboxDropParsed(payload: raw, location: location)
          }
          return
        }
        if let droppedId = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
          DispatchQueue.main.async {
            dropReceived(droppedId: droppedId, location: location)
          }
        }
      }
      return true
    }
    return false
  }

  private func handleStudentToInboxDropParsed(payload: String, location: CGPoint) {
    let parts = payload.split(separator: ":")
    guard parts.count == 4,
          parts[0] == "STUDENT_TO_INBOX",
          let sourceID = UUID(uuidString: String(parts[1])),
          let lessonID = UUID(uuidString: String(parts[2])),
          let studentID = UUID(uuidString: String(parts[3])) else { return }
    handleStudentToInboxDrop(sourceStudentLessonID: sourceID, lessonID: lessonID, studentID: studentID, location: location)
  }

  private func handleStudentToInboxDrop(sourceStudentLessonID: UUID, lessonID: UUID, studentID: UUID, location: CGPoint) {
    // 1) Find or create an unscheduled single-student StudentLesson for this lesson+student
    let targetSL: StudentLesson = {
      if let existing = studentLessons.first(where: { $0.lessonID == lessonID && $0.scheduledFor == nil && !$0.isGiven && $0.studentIDs == [studentID] }) {
        return existing
      }
      // Fetch Lesson and Student to set relationships first
      let lessonFetch = FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
      let studentFetch = FetchDescriptor<Student>(predicate: #Predicate { $0.id == studentID })
      let lessonObj = (try? modelContext.fetch(lessonFetch))?.first
      let studentObj = (try? modelContext.fetch(studentFetch))?.first
      let new = StudentLesson(
        id: UUID(),
        lessonID: lessonID,
        studentIDs: [studentID],
        createdAt: Date(),
        scheduledFor: nil,
        givenAt: nil,
        notes: "",
        needsPractice: false,
        needsAnotherPresentation: false,
        followUpWork: ""
      )
      new.lesson = lessonObj
      if let s = studentObj { new.students = [s] }
      new.syncSnapshotsFromRelationships()
      modelContext.insert(new)
      return new
    }()

    // 2) Remove the student from the source scheduled StudentLesson; delete it if empty
    if let src = studentLessons.first(where: { $0.id == sourceStudentLessonID }) {
      src.studentIDs.removeAll { $0 == studentID }
      src.students.removeAll { $0.id == studentID }
      if src.studentIDs.isEmpty {
        modelContext.delete(src)
      } else {
        src.syncSnapshotsFromRelationships()
      }
    }

    // 3) Insert the target into inbox order at the drop location
    let currentOrder = orderedUnscheduledLessons.map(\.id)
    var framesByID: [UUID: CGRect] = [:]
    for id in currentOrder {
      if let frame = itemFrames[id] { framesByID[id] = frame }
    }
    let insertionIndex = PlanningDropUtils.computeInsertionIndex(locationY: location.y, frames: framesByID)
    var newOrder = currentOrder
    newOrder.removeAll(where: { $0 == targetSL.id })
    let boundedIndex = max(0, min(insertionIndex, newOrder.count))
    newOrder.insert(targetSL.id, at: boundedIndex)
    let serialized = InboxOrderStore.serialize(newOrder)
    inboxOrderRaw = serialized
    onUpdateOrder?(serialized)
    try? modelContext.save()
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

      StudentLessonPill(snapshot: sl.snapshot(), day: Date(), targetStudentLessonID: sl.id)
        .onTapGesture {
          if isSelectionMode {
            onToggleSelected()
          } else {
            onOpenDetails(sl.id)
          }
        }
        .onDrag {
          let provider = NSItemProvider(object: NSString(string: sl.id.uuidString))
          provider.suggestedName = sl.lesson?.name ?? "Lesson"
          return provider
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

fileprivate struct InboxDropDelegate: DropDelegate {
  let getCurrent: () -> [StudentLesson]
  let itemFramesProvider: () -> [UUID: CGRect]
  let onTargetChange: (Bool) -> Void
  let onInsertionIndexChange: (Int?) -> Void
  let performDropHandler: ([NSItemProvider], CGPoint) -> Bool
  func dropEntered(info: DropInfo) {
    onTargetChange(true)
    onInsertionIndexChange(computeIndex(info))
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    onInsertionIndexChange(computeIndex(info))
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    onTargetChange(false)
    onInsertionIndexChange(nil)
  }

  func validateDrop(info: DropInfo) -> Bool {
    return info.hasItemsConforming(to: [UTType.text])
  }

  func performDrop(info: DropInfo) -> Bool {
    onTargetChange(false)
    onInsertionIndexChange(nil)
    let providers = info.itemProviders(for: [UTType.text])
    return performDropHandler(providers, info.location)
  }

  private func computeIndex(_ info: DropInfo) -> Int {
    let current = getCurrent()
    let frames = itemFramesProvider()
    let dict: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: current.compactMap { item in
      if let rect = frames[item.id] { return (item.id, rect) }
      return nil
    })
    return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
  }
}

