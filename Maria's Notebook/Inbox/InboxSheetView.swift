import SwiftUI
import CoreData
import UniformTypeIdentifiers

private struct InboxPillFramePreference: PreferenceKey {
  nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
  static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

public struct InboxSheetView: View {
  let lessonAssignments: [CDLessonAssignment]
  let orderedUnscheduledLessons: [CDLessonAssignment]
  @Binding var inboxOrderRaw: String

  let onOpenDetails: (UUID) -> Void
  let onQuickActions: (UUID) -> Void
  let onPlanNext: (CDLessonAssignment) -> Void
  let onUpdateOrder: ((String) -> Void)?

  @Environment(\.calendar) private var calendar
  @Environment(\.appRouter) private var appRouter
  @Environment(\.managedObjectContext) private var viewContext
  @Environment(SaveCoordinator.self) private var saveCoordinator
  @State private var viewModel = InboxSheetViewModel()

  @State private var itemFrames: [UUID: CGRect] = [:]
  @State private var spaceID = UUID()
  @State private var isTargeted = false
  @State private var insertionIndex: Int?
  @State private var baseFrames: [UUID: CGRect]?

  init(
    lessonAssignments: [CDLessonAssignment],
    orderedUnscheduledLessons: [CDLessonAssignment],
    inboxOrderRaw: Binding<String>,
    onOpenDetails: @escaping (UUID) -> Void,
    onQuickActions: @escaping (UUID) -> Void,
    onPlanNext: @escaping (CDLessonAssignment) -> Void,
    onUpdateOrder: ((String) -> Void)? = nil
  ) {
    self.lessonAssignments = lessonAssignments
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

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "tray")
          .imageScale(.large)
          .frame(width: 24, height: 24)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("📥 Inbox")
            .font(.headline)
            .foregroundStyle(.primary)
          Text("Unscheduled lessons")
            .font(.callout)
            .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        // Batch actions bar
        HStack(spacing: 8) {
          Button {
            viewModel.consolidateSelected(
              orderedUnscheduledLessons: orderedUnscheduledLessons,
              lessonAssignments: lessonAssignments,
              inboxOrderRaw: $inboxOrderRaw,
              viewContext: viewContext,
              appRouter: appRouter,
              saveCoordinator: saveCoordinator
            )
          } label: {
            Label("Consolidate Selected", systemImage: "arrow.triangle.merge")
          }
          .disabled(!viewModel.canConsolidate(orderedUnscheduledLessons: orderedUnscheduledLessons))

          if viewModel.isSelectionMode {
            Text("\(viewModel.selected.count) selected")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        ScrollView {
          VStack(spacing: 10) {
            ForEach(Array(orderedUnscheduledLessons.enumerated()), id: \.element.objectID) { _, sl in
              let slID = sl.id ?? UUID()
              InboxRow(
                sl: sl,
                slID: slID,
                isSelected: viewModel.selected.contains(slID),
                isSelectionMode: viewModel.isSelectionMode,
                spaceID: spaceID,
                onToggleSelected: {
                  viewModel.toggleSelection(slID)
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
          // Defer state update to next run loop to avoid layout recursion
          // PreferenceKey updates happen during layout, so we must defer state changes
          Task { @MainActor in
              itemFrames = prefs
          }
        }
        .onDrop(of: [UTType.text], delegate: InboxDropDelegate(
          getCurrent: { orderedUnscheduledLessons },
          itemFramesProvider: { baseFrames ?? itemFrames },
          onTargetChange: { targeted in
            adaptiveWithAnimation(.easeInOut(duration: 0.1)) { isTargeted = targeted }
            if targeted {
              if baseFrames == nil { baseFrames = itemFrames }
            } else {
              baseFrames = nil
            }
          },
          onInsertionIndexChange: { idx in
            if idx != insertionIndex {
              adaptiveWithAnimation(
                  .interactiveSpring(response: 0.16, dampingFraction: 0.85)
              ) { insertionIndex = idx }
            }
          },
          performDropHandler: { providers, location in
            viewModel.handleDrop(
              providers: providers,
              location: location,
              lessonAssignments: lessonAssignments,
              orderedUnscheduledLessons: orderedUnscheduledLessons,
              itemFrames: baseFrames ?? itemFrames,
              inboxOrderRaw: $inboxOrderRaw,
              viewContext: viewContext,
              saveCoordinator: saveCoordinator
            )
          }
        ))
        .overlay(
          GeometryReader { proxy in
            let placeholderWidth = max(0, proxy.size.width - 24) // content has 12pt horizontal padding on each side
            let placeholderHeight: CGFloat = 44

            Group {
              if let idx = insertionIndex {
                let frames: [(UUID, CGRect)] = orderedUnscheduledLessons.compactMap { item -> (UUID, CGRect)? in
                  guard let id = item.id, let rect = (baseFrames ?? itemFrames)[id] else { return nil }
                  return (id, rect)
                }.sorted { $0.1.minY < $1.1.minY }

                if frames.isEmpty {
                  // Empty list case: show placeholder near the top padding
                  let yTop = 10 + placeholderHeight / 2
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
                    .overlay(
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                    .frame(width: placeholderWidth, height: placeholderHeight)
                    .position(x: proxy.size.width / 2, y: yTop)
                    .transition(.opacity.combined(with: .scale))
                } else {
                  let y: CGFloat = {
                    if idx < frames.count {
                      return frames[idx].1.minY
                    } else if let lastFrame = frames.last {
                      return lastFrame.1.maxY
                    } else {
                      return 10
                    }
                  }()
                  let placeholderY = y + placeholderHeight / 2

                  // Spacer behind placeholder to reserve vertical space
                  Color.clear
                    .frame(width: placeholderWidth, height: placeholderHeight)
                    .position(x: proxy.size.width / 2, y: placeholderY)
                    .allowsHitTesting(false)

                  // Ghost placeholder
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
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
                    .shadow(color: Color.accentColor.opacity(UIConstants.OpacityConstants.semi), radius: 4)
                    .position(x: proxy.size.width / 2, y: y)
                }
              } else if isTargeted && orderedUnscheduledLessons.isEmpty {
                // No insertion index yet, but we are targeted and empty: hint at top
                let yTop = 10 + placeholderHeight / 2
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
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
            .stroke(isTargeted ? Color.accentColor.opacity(UIConstants.OpacityConstants.half) : Color.clear, lineWidth: 2)
        )
      }
    }
    .overlay(alignment: .top) {
      if let message = viewModel.toastMessage {
        Text(message)
          .font(AppTheme.ScaledFont.captionSemibold)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color.black.opacity(UIConstants.OpacityConstants.nearSolid))
          )
          .foregroundStyle(.white)
          .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
          .transition(.move(edge: .top).combined(with: .opacity))
          .padding(.top, 8)
      }
    }
    .onAppear {
      viewModel.onUpdateOrder = onUpdateOrder
    }
  }

}

private struct InboxRow: View {
  let sl: CDLessonAssignment
  let slID: UUID
  let isSelected: Bool
  let isSelectionMode: Bool
  let spaceID: UUID
  let onToggleSelected: () -> Void
  let onOpenDetails: (UUID) -> Void
  let onQuickActions: (UUID) -> Void
  let onPlanNext: (CDLessonAssignment) -> Void
  var body: some View {
    HStack(spacing: 8) {
      Button(action: onToggleSelected) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.plain)

      PresentationPill(snapshot: sl.snapshot(), day: Date(), targetLessonAssignmentID: slID)
        .onTapGesture {
          if isSelectionMode {
            onToggleSelected()
          } else {
            onOpenDetails(slID)
          }
        }
        .onDrag {
          let provider = NSItemProvider(object: NSString(string: slID.uuidString))
          provider.suggestedName = sl.lesson?.name ?? "Lesson"
          return provider
        }
        .contextMenu {
          Button { onQuickActions(slID) } label: { Label("Quick Actions…", systemImage: "bolt") }
          Button { onPlanNext(sl) } label: { Label("Plan Next Lesson in Group", systemImage: "calendar.badge.plus") }
          Button { onOpenDetails(slID) } label: { Label("Open Details", systemImage: "info.circle") }
        }
    }
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isSelected ? Color.accentColor.opacity(UIConstants.OpacityConstants.subtle) : Color.clear)
    )
    .contentShape(Rectangle())
    .background(
      GeometryReader { proxy in
        Color.clear
          .preference(
            key: InboxPillFramePreference.self,
            value: [slID: proxy.frame(in: .named(spaceID))]
          )
      }
    )
  }
}

private struct InboxDropDelegate: DropDelegate {
  let getCurrent: () -> [CDLessonAssignment]
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
    let dict: [UUID: CGRect] = Dictionary(
      current.compactMap { item -> (UUID, CGRect)? in
        guard let id = item.id, let rect = frames[id] else { return nil }
        return (id, rect)
      },
      uniquingKeysWith: { first, _ in first }
    )
    return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
  }
}
