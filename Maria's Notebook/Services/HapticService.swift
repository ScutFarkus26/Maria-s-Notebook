// HapticService.swift
// Centralized haptic feedback management

import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Provides centralized haptic feedback with pre-prepared generators for performance
@MainActor
final class HapticService {
    static let shared = HapticService()

    #if os(iOS)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    private init() {
        #if os(iOS)
        lightImpact.prepare()
        mediumImpact.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        #endif
    }

    /// Trigger an impact haptic
    func impact(_ style: HapticStyle = .medium) {
        #if os(iOS)
        switch style {
        case .light:
            lightImpact.impactOccurred()
            lightImpact.prepare()
        case .medium:
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
        case .heavy:
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
        }
        #endif
    }

    /// Trigger a notification haptic
    func notification(_ type: HapticNotificationType) {
        #if os(iOS)
        switch type {
        case .success:
            notificationGenerator.notificationOccurred(.success)
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
        case .error:
            notificationGenerator.notificationOccurred(.error)
        }
        notificationGenerator.prepare()
        #endif
    }

    /// Trigger a selection change haptic
    func selection() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }
}

// MARK: - Haptic Types

enum HapticStyle {
    case light
    case medium
    case heavy
}

enum HapticNotificationType {
    case success
    case warning
    case error
}
