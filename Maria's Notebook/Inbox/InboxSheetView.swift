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
  /// Loaded once by the parent and read by every row's pill. The pill owns no
  /// `@FetchRequest`: an unread one still builds a live fetched-results
  /// controller, and the inbox draws a pill per unscheduled presentation.
  let lessons: [CDLesson]
  let students: [CDStudent]
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
    lessons: [CDLesson],
    students: [CDStudent],
    inboxOrderRaw: Binding<String>,
    onOpenDetails: @escaping (UUID) -> Void,
    onQuickActions: @escaping (UUID) -> Void,
    onPlanNext: @escaping (CDLessonAssignment) -> Void,
    onUpdateOrder: ((String) -> Void)? = nil
  ) {
    self.lessonAssignments = lessonAssignments
    self.orderedUnscheduledLessons = orderedUnscheduledLessons
    self.lessons = lessons
    self.students = students
    self._inboxOrderRaw = inboxOrderRaw
    self.onOpenDetails = onOpenDetails
    self.onQuickActions = onQuickActions
    self.onPlanNext = onPlanNext
    self.onUpdateOrder = onUpdateOrder
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      inboxHeader
      inboxContent
    }
    .overlay(alignment: .top) {
      toastOverlay
    }
    .onAppear {
      viewModel.onUpdateOrder = onUpdateOrder
    }
  }

  private var inboxHeader: some View {
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
  }

  @ViewBuilder
  private var inboxContent: some View {
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
      batchActionsBar
      inboxScrollView
    }
  }

  private var batchActionsBar: some View {
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
  }

  private var inboxScrollView: some View {
    ScrollView {
      VStack(spacing: 10) {
        ForEach(Array(orderedUnscheduledLessons.enumerated()), id: \.element.objectID) { _, sl in
          let slID: UUID = sl.id ?? UUID()
          InboxRow(
            sl: sl,
            slID: slID,
            isSelected: viewModel.selected.contains(slID),
            isSelectionMode: viewModel.isSelectionMode,
            spaceID: spaceID,
            lessons: lessons,
            students: students,
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
      dropPlaceholderOverlay
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isTargeted ? Color.accentColor.opacity(UIConstants.OpacityConstants.half) : Color.clear, lineWidth: 2)
    )
  }

}

// The drop placeholder and the toast live in an extension so the view's own
// body stays inside SwiftLint's type-length limit.
extension InboxSheetView {

  private var dropPlaceholderOverlay: some View {
    GeometryReader { proxy in
      let placeholderWidth: CGFloat = max(0, proxy.size.width - 24)
      let placeholderHeight: CGFloat = 44

      Group {
        if let idx = insertionIndex {
          let frames: [(UUID, CGRect)] = orderedUnscheduledLessons.compactMap { item -> (UUID, CGRect)? in
            guard let id = item.id, let rect = (baseFrames ?? itemFrames)[id] else { return nil }
            return (id, rect)
          }.sorted { $0.1.minY < $1.1.minY }

          if frames.isEmpty {
            let yTop: CGFloat = 10 + placeholderHeight / 2
            dropPlaceholderRect(width: placeholderWidth, height: placeholderHeight)
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
            let placeholderY: CGFloat = y + placeholderHeight / 2

            Color.clear
              .frame(width: placeholderWidth, height: placeholderHeight)
              .position(x: proxy.size.width / 2, y: placeholderY)
              .allowsHitTesting(false)

            dropPlaceholderRect(width: placeholderWidth, height: placeholderHeight)
              .position(x: proxy.size.width / 2, y: placeholderY)
              .transition(.opacity.combined(with: .scale))

            Capsule()
              .fill(Color.accentColor)
              .frame(width: placeholderWidth, height: 3)
              .shadow(color: Color.accentColor.opacity(UIConstants.OpacityConstants.semi), radius: 4)
              .position(x: proxy.size.width / 2, y: y)
          }
        } else if isTargeted && orderedUnscheduledLessons.isEmpty {
          let yTop: CGFloat = 10 + placeholderHeight / 2
          dropPlaceholderRect(width: placeholderWidth, height: placeholderHeight)
            .position(x: proxy.size.width / 2, y: yTop)
            .transition(.opacity.combined(with: .scale))
        }
      }
    }
  }

  private func dropPlaceholderRect(width: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.subtle))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
      )
      .frame(width: width, height: height)
  }

  @ViewBuilder
  private var toastOverlay: some View {
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
}

private struct InboxRow: View {
  let sl: CDLessonAssignment
  let slID: UUID
  let isSelected: Bool
  let isSelectionMode: Bool
  let spaceID: UUID
  let lessons: [CDLesson]
  let students: [CDStudent]
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

      PresentationPill(
        snapshot: sl.snapshot(),
        day: Date(),
        targetLessonAssignmentID: slID,
        cachedLessons: lessons,
        cachedStudents: students
      )
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
