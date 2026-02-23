//
//  ErrorViews.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import SwiftUI

// MARK: - Error Banner View

/// Inline banner for displaying non-critical errors
struct ErrorBanner: View {
    let error: any AppError
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(error.errorDescription ?? "Error")
                    .font(.headline)
                
                if let reason = error.failureReason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var iconName: String {
        switch error.severity {
        case .debug, .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error, .critical:
            return "xmark.octagon.fill"
        }
    }
    
    private var iconColor: Color {
        switch error.severity {
        case .debug, .info:
            return .blue
        case .warning:
            return .orange
        case .error, .critical:
            return .red
        }
    }
    
    private var backgroundColor: Color {
        switch error.severity {
        case .debug, .info:
            return Color.blue.opacity(0.1)
        case .warning:
            return Color.orange.opacity(0.1)
        case .error, .critical:
            return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Error Detail View

/// Full-screen error detail view for critical errors
struct ErrorDetailView: View {
    let error: any AppError
    let onDismiss: () -> Void
    let onRetry: (() async -> Void)?
    
    @State private var isRetrying = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Error icon
            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)
            
            // Title
            Text(error.errorDescription ?? "Error")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Failure reason
            if let reason = error.failureReason {
                Text(reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Suggested Action", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    Text(suggestion)
                        .font(.body)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                if let onRetry = onRetry, error.isRecoverable {
                    Button {
                        Task {
                            isRetrying = true
                            await onRetry()
                            isRetrying = false
                        }
                    } label: {
                        if isRetrying {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Retry")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)
                }
                
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding()
    }
    
    private var iconName: String {
        switch error.severity {
        case .debug, .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error, .critical:
            return "xmark.octagon"
        }
    }
    
    private var iconColor: Color {
        switch error.severity {
        case .debug, .info:
            return .blue
        case .warning:
            return .orange
        case .error, .critical:
            return .red
        }
    }
}

// MARK: - Error Empty State

/// Empty state view with error information
struct ErrorEmptyState: View {
    let error: any AppError
    let retryAction: (() async -> Void)?
    
    @State private var isRetrying = false
    
    var body: some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Error", systemImage: iconName)
        } description: {
            if let reason = error.failureReason {
                Text(reason)
            }
        } actions: {
            if let retryAction = retryAction, error.isRecoverable {
                Button {
                    Task {
                        isRetrying = true
                        await retryAction()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Try Again")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
            }
        }
    }
    
    private var iconName: String {
        switch error.category {
        case .validation:
            return "exclamationmark.triangle"
        case .notFound:
            return "magnifyingglass"
        case .conflict:
            return "arrow.triangle.merge"
        case .permission:
            return "lock"
        case .database:
            return "externaldrive.badge.xmark"
        case .network:
            return "wifi.slash"
        case .business:
            return "exclamationmark.circle"
        case .system:
            return "exclamationmark.octagon"
        }
    }
}

// MARK: - Previews

#Preview("Error Banner - Warning") {
    VStack {
        ErrorBanner(
            error: StudentError.duplicateName(firstName: "John", lastName: "Doe"),
            onDismiss: {}
        )
        .padding()
        Spacer()
    }
}

#Preview("Error Banner - Critical") {
    VStack {
        ErrorBanner(
            error: SyncError.dataCorrupted(entity: "Student"),
            onDismiss: {}
        )
        .padding()
        Spacer()
    }
}

#Preview("Error Detail View") {
    ErrorDetailView(
        error: WorkError.cannotCompleteWithIncompleteSteps(incompleteCount: 3),
        onDismiss: {},
        onRetry: {}
    )
}

#Preview("Error Empty State") {
    ErrorEmptyState(
        error: SyncError.networkUnavailable,
        retryAction: {}
    )
}
