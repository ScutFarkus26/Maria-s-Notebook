//
//  ErrorHandling.swift
//  Maria's Notebook
//
//  Created by Architecture Migration on 2026-02-13.
//

import Foundation
import SwiftUI
import OSLog

// MARK: - Error Logging

extension AppError {
    /// Log this error with appropriate severity
    func log(logger: Logger = .app(category: "Errors"), context: [String: Any] = [:]) {
        let message = """
        [\(code)] \(errorDescription ?? "Unknown error")
        Category: \(category.rawValue)
        Recoverable: \(isRecoverable)
        \(failureReason.map { "Reason: \($0)" } ?? "")
        \(recoverySuggestion.map { "Recovery: \($0)" } ?? "")
        \(context.isEmpty ? "" : "Context: \(context)")
        """
        
        switch severity {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }
}

// MARK: - Result Extensions

extension Result where Failure: AppError {
    /// Map success value while preserving error
    func tryMap<NewSuccess>(_ transform: (Success) throws -> NewSuccess) -> Result<NewSuccess, Error> {
        switch self {
        case .success(let value):
            do {
                return .success(try transform(value))
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Log error if failed
    @discardableResult
    func logError(logger: Logger = .app(category: "Errors"), context: [String: Any] = [:]) -> Self {
        if case .failure(let error) = self {
            error.log(logger: logger, context: context)
        }
        return self
    }
}

// MARK: - Error Presentation Models

/// Presentation model for displaying errors to users
struct ErrorPresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: ErrorSeverity
    let actions: [ErrorAction]
    
    init(from error: AppError, context: String? = nil) {
        self.title = error.errorDescription ?? "Error"
        
        var message = error.failureReason ?? ""
        if let recovery = error.recoverySuggestion {
            if !message.isEmpty {
                message += "\n\n"
            }
            message += recovery
        }
        if let context = context {
            if !message.isEmpty {
                message += "\n\n"
            }
            message += "Context: \(context)"
        }
        
        self.message = message
        self.severity = error.severity
        
        // Default actions based on recoverability
        if error.isRecoverable {
            self.actions = [
                .init(title: "OK", style: .default, isPreferred: true, action: {})
            ]
        } else {
            self.actions = [
                .init(title: "Dismiss", style: .cancel, isPreferred: true, action: {})
            ]
        }
    }
    
    init(title: String, message: String, severity: ErrorSeverity = .error, actions: [ErrorAction] = []) {
        self.title = title
        self.message = message
        self.severity = severity
        self.actions = actions.isEmpty ? [.init(title: "OK", style: .default, isPreferred: true, action: {})] : actions
    }
}

struct ErrorAction: Identifiable {
    let id = UUID()
    let title: String
    let style: ActionStyle
    let isPreferred: Bool
    let action: () -> Void
    
    enum ActionStyle {
        case `default`
        case cancel
        case destructive
    }
    
    init(title: String, style: ActionStyle = .default, isPreferred: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.isPreferred = isPreferred
        self.action = action
    }
}

// MARK: - SwiftUI Error Handling

extension View {
    /// Present an error alert
    func errorAlert(
        error: Binding<(any AppError)?>,
        context: String? = nil
    ) -> some View {
        self.modifier(ErrorAlertModifier(error: error, context: context))
    }
    
    /// Present an error with custom presentation
    func errorPresentation(
        presentation: Binding<ErrorPresentation?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        self.modifier(ErrorPresentationModifier(presentation: presentation, onDismiss: onDismiss))
    }
}

private struct ErrorAlertModifier: ViewModifier {
    @Binding var error: (any AppError)?
    let context: String?
    @State private var presentation: ErrorPresentation?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: error) { _, newError in
                if let error = newError {
                    presentation = ErrorPresentation(from: error, context: context)
                    error.log(context: context.map { ["context": $0] } ?? [:])
                }
            }
            .alert(
                presentation?.title ?? "Error",
                isPresented: .constant(presentation != nil),
                presenting: presentation
            ) { presentation in
                ForEach(presentation.actions) { action in
                    Button(action.title, role: buttonRole(for: action.style)) {
                        action.action()
                        self.presentation = nil
                        self.error = nil
                    }
                }
            } message: { presentation in
                Text(presentation.message)
            }
    }
    
    private func buttonRole(for style: ErrorAction.ActionStyle) -> ButtonRole? {
        switch style {
        case .default: return nil
        case .cancel: return .cancel
        case .destructive: return .destructive
        }
    }
}

private struct ErrorPresentationModifier: ViewModifier {
    @Binding var presentation: ErrorPresentation?
    let onDismiss: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert(
                presentation?.title ?? "Error",
                isPresented: .constant(presentation != nil),
                presenting: presentation
            ) { presentation in
                ForEach(presentation.actions) { action in
                    Button(action.title, role: buttonRole(for: action.style)) {
                        action.action()
                        self.presentation = nil
                        onDismiss?()
                    }
                }
            } message: { presentation in
                Text(presentation.message)
            }
    }
    
    private func buttonRole(for style: ErrorAction.ActionStyle) -> ButtonRole? {
        switch style {
        case .default: return nil
        case .cancel: return .cancel
        case .destructive: return .destructive
        }
    }
}

// MARK: - Error Recovery

/// Protocol for objects that can handle error recovery
protocol ErrorRecoverable {
    func canRecover(from error: AppError) -> Bool
    func recover(from error: AppError) async throws
}

/// Helper to wrap throwing operations with error handling
@MainActor
func withErrorHandling<T>(
    _ operation: () async throws -> T,
    onError: ((any Error) -> Void)? = nil
) async -> Result<T, Error> {
    do {
        let result = try await operation()
        return .success(result)
    } catch {
        onError?(error)
        if let appError = error as? AppError {
            appError.log()
        }
        return .failure(error)
    }
}

/// Helper to convert throwing functions to Result-based functions
func resultify<T>(_ operation: () throws -> T) -> Result<T, Error> {
    do {
        return .success(try operation())
    } catch {
        return .failure(error)
    }
}

/// Helper to convert async throwing functions to Result-based functions
func resultify<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}
