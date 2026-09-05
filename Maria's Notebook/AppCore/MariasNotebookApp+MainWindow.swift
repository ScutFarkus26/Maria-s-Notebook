//
//  MariasNotebookApp+MainWindow.swift
//  Maria's Notebook
//
//  The main window's root content: the loading and restoring placeholders,
//  onboarding, and the ready-state RootView with the app environment applied.
//

import OSLog
import SwiftUI

extension MariasNotebookApp {
    // MARK: - Computed Properties

    var loadingMessage: String {
        switch bootstrapper.state {
        case .idle:
            return "Starting up..."
        case .initializingContainer:
            return "Initializing database..."
        case .migrating:
            return "Running migrations..."
        case .ready:
            return "Ready"
        }
    }

    // MARK: - App Flow Content

    @ViewBuilder
    var appFlowContent: some View {
        if bootstrapper.state == .ready {
            readyContent
        } else {
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text(loadingMessage)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    var readyContent: some View {
        if restoreCoordinator.isRestoring {
            VStack(spacing: 20) {
                ProgressView().controlSize(.large)
                Text("Restoring data…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        } else if !hasCompletedOnboarding {
            OnboardingView()
        } else {
            RootView(classroomWorkspace: classroomWorkspace)
                .activeClassroomEnvironment(classroomWorkspace)
                .environment(\.calendar, AppCalendar.shared)
                .environment(\.appRouter, appRouter)
                .environment(saveCoordinator)
                .environment(restoreCoordinator)
                .environment(AlbumLibrary.shared)
                .syncingFromICloudOverlay()
        }
    }

    private static let logger = Logger.app(category: "App")

    var mainWindowContent: some View {
        Group {
            if databaseErrorCoordinator.error != nil || AppBootstrapping.initError != nil {
                DatabaseErrorView(errorCoordinator: databaseErrorCoordinator, appRouter: appRouter)
            } else {
                appFlowContent
            }
        }
        // Log state transitions, not evaluations: this body re-runs on every
        // change to the observed coordinators, and building a Logger plus two
        // log lines per evaluation sat on the hottest path in the app.
        .onChange(of: bootstrapper.state, initial: true) { _, state in
            Self.logger.info("App body: bootstrapper state: \(String(describing: state))")
        }
    }

    #if os(macOS)
    var settingsUnavailableMessage: String {
        if restoreCoordinator.isRestoring {
            return "Settings will be available when the restore finishes."
        }
        if !hasCompletedOnboarding {
            return "Finish setup in the main window to use Settings."
        }
        return loadingMessage
    }
    #endif
}
