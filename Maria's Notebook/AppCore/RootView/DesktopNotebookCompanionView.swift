#if os(macOS)
import Combine
import SwiftUI
import CoreData
import AppKit

/// A small floating macOS home for the notebook companion. The window contains
/// counts only; opening an action brings the main app forward before navigating.
struct DesktopNotebookCompanionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage(UserDefaultsKeys.notebookCompanionVisible)
    private var isVisible = true
    @AppStorage(UserDefaultsKeys.notebookCompanionDetached)
    private var isDetached = false
    @AppStorage(UserDefaultsKeys.notebookCompanionHasDesktopPosition)
    private var hasSavedDesktopPosition = false
    @AppStorage(UserDefaultsKeys.notebookCompanionDesktopX)
    private var savedDesktopX = 0.0
    @AppStorage(UserDefaultsKeys.notebookCompanionDesktopY)
    private var savedDesktopY = 0.0

    @State private var viewModel = NotebookCompanionViewModel()
    @State private var isPanelPresented = false
    @State private var windowController = DetachedCompanionWindowController()
    @State private var dragAnchor: DesktopCompanionDragAnchor?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NotebookCompanionCharacter(
                state: viewModel.snapshot.state(isWorking: appRouter.isAIWorking)
            )

            if viewModel.snapshot.attentionCount > 0 {
                Text(viewModel.snapshot.attentionCount > 9 ? "9+" : "\(viewModel.snapshot.attentionCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(.red))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 62, height: 62)
        .padding(13)
        .contentShape(Rectangle())
        .onTapGesture(perform: openPanel)
        .gesture(windowDragGesture)
        .help("Robot teacher — drag anywhere to move, click for help")
        .contextMenu { contextMenu }
        .popover(isPresented: $isPanelPresented, arrowEdge: .bottom) {
            companionPanel
        }
        .background(
            DetachedCompanionWindowConfigurator(
                controller: windowController,
                savedOrigin: savedDesktopOrigin
            )
        )
        .frame(width: 88, height: 88)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the notebook companion")
        .onAppear {
            isVisible = true
            isDetached = true
            viewModel.configure(context: viewContext)
        }
        .onChange(of: isVisible) { _, shouldShow in
            if !shouldShow {
                isPanelPresented = false
                dismissWindow(id: "notebookCompanion")
            }
        }
        // Debounce: objectsDidChange fires per change, not per save, so a single
        // CloudKit merge can post it hundreds of times — and each reload runs the
        // companion's count queries. Coalesce them (same pattern as StudentsView).
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        ) { _ in
            viewModel.reload(calendar: calendar)
        }
        .onCalendarDayChange {
            viewModel.reload(calendar: calendar)
        }
    }

    private var savedDesktopOrigin: CGPoint? {
        guard hasSavedDesktopPosition else { return nil }
        return CGPoint(x: savedDesktopX, y: savedDesktopY)
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                isPanelPresented = false
                if dragAnchor == nil {
                    dragAnchor = windowController.beginDrag()
                }
                if let dragAnchor {
                    windowController.dragWindow(from: dragAnchor)
                }
            }
            .onEnded { _ in
                dragAnchor = nil
                if let origin = windowController.windowOrigin {
                    savedDesktopX = origin.x
                    savedDesktopY = origin.y
                    hasSavedDesktopPosition = true
                }
            }
    }

    private var companionPanel: some View {
        NotebookCompanionPanel(
            snapshot: viewModel.snapshot,
            isWorking: appRouter.isAIWorking,
            onPlanDay: {
                performInMainApp {
                    appRouter.requestAIQuestion(viewModel.snapshot.briefingPrompt)
                }
            },
            onFindFollowUps: {
                performInMainApp {
                    appRouter.requestAIQuestion(NotebookCompanionSnapshot.followUpPrompt)
                }
            },
            onSuggestPresentations: {
                performInMainApp {
                    appRouter.requestAIQuestion(NotebookCompanionSnapshot.presentationPrompt)
                }
            },
            onAskAnything: {
                performInMainApp {
                    appRouter.navigateTo(.askAI)
                }
            },
            onQuickCapture: {
                performInMainApp {
                    appRouter.triggerCommandBar = true
                }
            },
            onReviewTodos: {
                performInMainApp {
                    appRouter.navigateTo(.todos)
                }
            },
            placementAction: .returnToApp,
            onChangePlacement: returnToApp,
            onHide: hideCompanion
        )
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open Companion", systemImage: "graduationcap.fill", action: openPanel)
        Button("Ask My Notebook", systemImage: "bubble.left.and.text.bubble.right") {
            performInMainApp { appRouter.navigateTo(.askAI) }
        }
        Button("Make My Short Plan", systemImage: "list.bullet.clipboard.fill") {
            performInMainApp {
                appRouter.requestAIQuestion(viewModel.snapshot.briefingPrompt)
            }
        }
        Divider()
        Button("Return to App", systemImage: "rectangle.inset.filled", action: returnToApp)
        Button("Hide Companion", systemImage: "eye.slash", role: .destructive, action: hideCompanion)
    }

    private var accessibilityLabel: String {
        if appRouter.isAIWorking {
            return "Notebook companion, checking your notebook"
        }
        if viewModel.snapshot.attentionCount > 0 {
            return "Notebook companion, \(viewModel.snapshot.attentionCount) overdue items"
        }
        return "Notebook companion"
    }

    private func openPanel() {
        viewModel.reload(calendar: calendar)
        isPanelPresented = true
    }

    private func returnToApp() {
        isPanelPresented = false
        isDetached = false
        openWindow(id: "mainWindow")
        NSApp.activate(ignoringOtherApps: true)
        dismissWindow(id: "notebookCompanion")
    }

    private func hideCompanion() {
        isPanelPresented = false
        isVisible = false
    }

    private func performInMainApp(_ action: @escaping @MainActor () -> Void) {
        isPanelPresented = false
        openWindow(id: "mainWindow")
        NSApp.activate(ignoringOtherApps: true)

        // Give a newly reopened main window time to install its navigation
        // observers before sending the requested action.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            action()
        }
    }
}

/// Applies desktop-pet window behavior without turning the companion itself
/// into an AppKit view.
private struct DetachedCompanionWindowConfigurator: NSViewRepresentable {
    let controller: DetachedCompanionWindowController
    let savedOrigin: CGPoint?

    func makeNSView(context: Context) -> DetachedCompanionConfigurationView {
        let view = DetachedCompanionConfigurationView()
        view.controller = controller
        view.savedOrigin = savedOrigin
        return view
    }

    func updateNSView(_ nsView: DetachedCompanionConfigurationView, context: Context) {
        nsView.controller = controller
        nsView.savedOrigin = savedOrigin
        nsView.scheduleConfiguration()
    }
}

private final class DetachedCompanionConfigurationView: NSView {
    private var isConfigured = false
    var controller: DetachedCompanionWindowController?
    var savedOrigin: CGPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        guard !isConfigured, window != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.level = .floating
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            self.controller?.window = window
            self.controller?.restoreSavedOrigin(self.savedOrigin)
            self.isConfigured = true
        }
    }
}

private struct DesktopCompanionDragAnchor {
    let mouseLocation: CGPoint
    let windowOrigin: CGPoint
}

@MainActor
private final class DetachedCompanionWindowController {
    weak var window: NSWindow?

    var windowOrigin: CGPoint? {
        window?.frame.origin
    }

    func beginDrag() -> DesktopCompanionDragAnchor? {
        guard let window else { return nil }
        return DesktopCompanionDragAnchor(
            mouseLocation: NSEvent.mouseLocation,
            windowOrigin: window.frame.origin
        )
    }

    func dragWindow(from anchor: DesktopCompanionDragAnchor) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(
            x: anchor.windowOrigin.x + mouse.x - anchor.mouseLocation.x,
            y: anchor.windowOrigin.y + mouse.y - anchor.mouseLocation.y
        )
        window.setFrameOrigin(origin)
    }

    func restoreSavedOrigin(_ origin: CGPoint?) {
        guard let window, let origin else { return }
        let proposedFrame = NSRect(origin: origin, size: window.frame.size)
        let isVisible = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(proposedFrame)
            return overlap.width >= 24 && overlap.height >= 24
        }
        if isVisible {
            window.setFrameOrigin(origin)
        }
    }
}
#endif
