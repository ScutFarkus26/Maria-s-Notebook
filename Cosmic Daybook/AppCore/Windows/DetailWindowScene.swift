//
//  DetailWindowScene.swift
//  Cosmic Daybook
//
//  One template for every "open X in its own window" scene on the Mac.
//
//  Each detail window used to spell out the same gate (wait for the store,
//  wait for a restore), the same environment stack, and the same "nothing
//  selected" placeholder. The scenes now differ only in what they present,
//  which this template takes as parameters.
//

#if os(macOS)
import SwiftUI

/// The app-wide objects every detail window injects into its host view.
/// The classroom workspace and save coordinator come from the open notebook,
/// which exists only once its stores are open.
struct DetailWindowDependencies {
    let bootstrapper: AppBootstrapper
    let restoreCoordinator: RestoreCoordinator
    let notebookOpener: NotebookOpener
    let appRouter: AppRouter
}

/// How a detail window looks while the store is loading or restoring.
enum DetailWindowLoadingStyle {
    /// A large spinner over a secondary caption.
    case stacked
    /// A `ProgressView` with the caption as its label.
    case labeled
}

/// What a detail window shows when it was opened without a value.
enum DetailWindowPlaceholder {
    /// Plain text, framed to the window's minimum size.
    case text(String)
    /// A `ContentUnavailableView`; `framed` applies the minimum size.
    case unavailable(String, systemImage: String, framed: Bool = true)
}

/// A `WindowGroup` presenting one value in its own window, gated on the
/// database being ready and no restore being in flight.
struct DetailWindowScene<Value: Codable & Hashable, Host: View>: Scene {
    private let id: String
    private let dependencies: DetailWindowDependencies
    private let defaultSize: CGSize
    private let minimumSize: CGSize
    private let loadingStyle: DetailWindowLoadingStyle
    private let placeholder: DetailWindowPlaceholder
    /// Whether the window holds typing (an observation, a topic, a meeting or
    /// report), so a classroom switch asks before closing it. Every detail
    /// window closes on a switch either way.
    private let countsAsEditor: Bool
    private let host: (Value) -> Host

    init(
        id: String,
        for _: Value.Type,
        dependencies: DetailWindowDependencies,
        defaultSize: CGSize,
        minimumSize: CGSize = CGSize(width: 400, height: 300),
        loadingStyle: DetailWindowLoadingStyle = .stacked,
        placeholder: DetailWindowPlaceholder,
        countsAsEditor: Bool,
        @ViewBuilder host: @escaping (Value) -> Host
    ) {
        self.id = id
        self.dependencies = dependencies
        self.defaultSize = defaultSize
        self.minimumSize = minimumSize
        self.loadingStyle = loadingStyle
        self.placeholder = placeholder
        self.countsAsEditor = countsAsEditor
        self.host = host
    }

    var body: some Scene {
        WindowGroup("", id: id, for: Value.self) { $value in
            if let value {
                DetailWindowGate(
                    dependencies: dependencies,
                    minimumSize: minimumSize,
                    loadingStyle: loadingStyle,
                    countsAsEditor: countsAsEditor
                ) {
                    host(value)
                }
            } else {
                placeholderView
            }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.automatic)
        .defaultSize(width: defaultSize.width, height: defaultSize.height)
    }

    @ViewBuilder
    private var placeholderView: some View {
        switch placeholder {
        case .text(let text):
            Text(text)
                .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        case .unavailable(let title, let systemImage, let framed):
            if framed {
                ContentUnavailableView(title, systemImage: systemImage)
                    .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
            } else {
                ContentUnavailableView(title, systemImage: systemImage)
            }
        }
    }
}

/// Shows the loading placeholder until the store is ready, then the host
/// with the shared environment applied.
///
/// A classroom switch closes the window rather than rebuilding it on the other
/// classroom's records, where its record isn't (bug hunt 2026-10-17 #31). A
/// window that holds typing counts itself in `OpenDetailWindows` while its
/// host is on screen, so a switch asks first (`DetailWindowClassroom`).
private struct DetailWindowGate<Host: View>: View {
    let dependencies: DetailWindowDependencies
    let minimumSize: CGSize
    let loadingStyle: DetailWindowLoadingStyle
    @ViewBuilder let host: () -> Host

    @Environment(\.dismissWindow) private var dismissWindow
    /// This window's part in a classroom switch.
    @State private var classroom: DetailWindowClassroom

    init(
        dependencies: DetailWindowDependencies,
        minimumSize: CGSize,
        loadingStyle: DetailWindowLoadingStyle,
        countsAsEditor: Bool,
        @ViewBuilder host: @escaping () -> Host
    ) {
        self.dependencies = dependencies
        self.minimumSize = minimumSize
        self.loadingStyle = loadingStyle
        self.host = host
        _classroom = State(initialValue: DetailWindowClassroom(countsAsEditor: countsAsEditor))
    }

    private var isRestoring: Bool { dependencies.restoreCoordinator.isRestoring }

    private var selection: ClassroomWorkspace? {
        dependencies.notebookOpener.notebook?.classroomWorkspace.selection
    }

    var body: some View {
        gatedContent
            .onChange(of: selection) { _, switchedTo in
                if let switchedTo { classroom.classroomChanged(to: switchedTo) }
            }
    }

    @ViewBuilder
    private var gatedContent: some View {
        if dependencies.bootstrapper.state == .ready, !isRestoring,
           let notebook = dependencies.notebookOpener.notebook {
            let workspace = notebook.classroomWorkspace
            if let openedIn = classroom.openedIn, classroom.isClosing(showing: workspace.selection) {
                closingView(openedIn: openedIn, showing: workspace.selection)
            } else {
                host()
                    .activeClassroomEnvironment(workspace)
                    .environment(\.calendar, AppCalendar.shared)
                    .environment(\.appRouter, dependencies.appRouter)
                    .environment(notebook.saveCoordinator)
                    .environment(dependencies.restoreCoordinator)
                    .onAppear { classroom.hostAppeared(showing: workspace.selection) }
                    .onDisappear { classroom.hostDisappeared() }
            }
        } else {
            loadingView
                .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        }
    }

    /// What the window shows once its classroom has been switched away: it
    /// closes on its own, but one that can't (a sheet still closing in it)
    /// says why it's empty and offers to close (review c #4).
    private func closingView(openedIn: ClassroomWorkspace, showing current: ClassroomWorkspace) -> some View {
        ContentUnavailableView {
            Label("This Window Was for \(openedIn.displayName)", systemImage: openedIn.systemImage)
        } description: {
            Text("You switched to \(current.displayName).")
        } actions: {
            Button("Close Window") { dismissWindow() }
        }
        .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        // On the next turn, once the host has gone, and with it anything that
        // held the window open (a topic with unsaved edits disables closing).
        // A sheet the host had up may still be closing, so it tries once more.
        .task {
            await Task.yield()
            dismissWindow()
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            dismissWindow()
        }
    }

    private var loadingMessage: String {
        isRestoring ? "Restoring your backup…" : "Loading…"
    }

    @ViewBuilder
    private var loadingView: some View {
        switch loadingStyle {
        case .stacked:
            VStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text(loadingMessage)
                    .foregroundStyle(.secondary)
            }
        case .labeled:
            ProgressView(loadingMessage)
        }
    }
}
#endif
