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

  @Environment(\.modelContext) private var modelContext
  @State private var itemFrames: [UUID: CGRect] = [:]
  @State private var spaceID = UUID()
  @State private var isTargeted = false

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
        ScrollView {
          VStack(spacing: 10) {
            ForEach(orderedUnscheduledLessons, id: \.id) { sl in
              StudentLessonPill(snapshot: sl.snapshot(), day: Date())
                .contentShape(Rectangle())
                .onTapGesture { onOpenDetails(sl.id) }
                .onDrag {
                  return NSItemProvider(object: sl.id.uuidString as NSString)
                }
                .contextMenu {
                  Button("Open Details") { onOpenDetails(sl.id) }
                  Button("Quick Actions") { onQuickActions(sl.id) }
                  Button("Plan Next") { onPlanNext(sl) }
                }
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
    let framesByID: [UUID: CGRect] = Dictionary(uniqueKeysWithValues: currentOrder.compactMap { id in
      itemFrames[id].map { (id, $0) }
    })
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

