//
//  DetailWindowScene.swift
//  Maria's Notebook
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
struct DetailWindowDependencies {
    let bootstrapper: AppBootstrapper
    let restoreCoordinator: RestoreCoordinator
    let classroomWorkspace: ClassroomWorkspaceStore
    let appRouter: AppRouter
    let saveCoordinator: SaveCoordinator
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
    private let host: (Value) -> Host

    init(
        id: String,
        for _: Value.Type,
        dependencies: DetailWindowDependencies,
        defaultSize: CGSize,
        minimumSize: CGSize = CGSize(width: 400, height: 300),
        loadingStyle: DetailWindowLoadingStyle = .stacked,
        placeholder: DetailWindowPlaceholder,
        @ViewBuilder host: @escaping (Value) -> Host
    ) {
        self.id = id
        self.dependencies = dependencies
        self.defaultSize = defaultSize
        self.minimumSize = minimumSize
        self.loadingStyle = loadingStyle
        self.placeholder = placeholder
        self.host = host
    }

    var body: some Scene {
        WindowGroup("", id: id, for: Value.self) { $value in
            if let value {
                DetailWindowGate(
                    dependencies: dependencies,
                    minimumSize: minimumSize,
                    loadingStyle: loadingStyle
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
private struct DetailWindowGate<Host: View>: View {
    let dependencies: DetailWindowDependencies
    let minimumSize: CGSize
    let loadingStyle: DetailWindowLoadingStyle
    @ViewBuilder let host: () -> Host

    private var isRestoring: Bool { dependencies.restoreCoordinator.isRestoring }

    var body: some View {
        if dependencies.bootstrapper.state != .ready || isRestoring {
            loadingView
                .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        } else {
            host()
                .activeClassroomEnvironment(dependencies.classroomWorkspace)
                .environment(\.calendar, AppCalendar.shared)
                .environment(\.appRouter, dependencies.appRouter)
                .environment(dependencies.saveCoordinator)
                .environment(dependencies.restoreCoordinator)
        }
    }

    private var loadingMessage: String {
        isRestoring ? "Restoring data…" : "Loading…"
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
