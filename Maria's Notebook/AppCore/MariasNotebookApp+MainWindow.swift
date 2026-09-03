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

    var mainWindowContent: some View {
        let logger: Logger = Logger.app(category: "App")
        // swiftlint:disable:next redundant_discardable_let
        let _ = logger.info("App body: Starting scene body evaluation")
        let stateDesc: String = String(describing: bootstrapper.state)
        // swiftlint:disable:next redundant_discardable_let
        let _ = logger.info("App body: bootstrapper state: \(stateDesc)")

        return Group {
            if databaseErrorCoordinator.error != nil || AppBootstrapping.initError != nil {
                DatabaseErrorView(errorCoordinator: databaseErrorCoordinator, appRouter: appRouter)
            } else {
                appFlowContent
            }
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
